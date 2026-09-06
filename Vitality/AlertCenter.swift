import Combine
import Foundation
import OSLog
import SwiftUI
import UserNotifications

/// The alerts Vitality knows how to raise.
///
/// The raw values are persisted (per-rule switches, snooze and cooldown dates),
/// so they are part of the on-disk format and must not be renamed.
enum AlertRuleID: String, CaseIterable, Identifiable {
    case diskFull, cpuSustained, swapHeavy, tempHigh, batteryLow

    var id: String { rawValue }
}

/// Where an alert can send you.
enum AlertAction { case openStorage, openActivity, openSensors, openPower, none }

struct ActiveAlert: Identifiable {
    let id: AlertRuleID
    let severity: Severity.Level
    let title: String
    let detail: String
    let actionLabel: String?
    let action: AlertAction
}

/// The settings-pane face of a rule: what it watches and when it fires, without
/// any of the live state.
struct AlertRuleInfo: Identifiable {
    let id: AlertRuleID
    let title: String
    let detail: String
    let icon: String
}

/// Turns the poll stream into a small, stable list of things that are actually
/// wrong, and — at most once every six hours per rule — says so out loud.
///
/// Two ideas do most of the work here:
///
/// **Hysteresis.** Every rule has a firing threshold and a lower release
/// threshold, and the band between them is deliberately dead. A disk hovering
/// at 90.0% would otherwise raise and clear an alert on alternate polls, and a
/// warning that blinks is a warning nobody reads. Once an alert is up it stays
/// up until the reading falls back past the release threshold — 88% for the
/// disk, 75% for CPU, and so on.
///
/// **A decaying counter.** "Sustained" cannot mean "120 unbroken samples": one
/// idle second in two minutes would reset the clock forever on a machine that
/// is plainly pinned. So the counter climbs by one while the condition holds
/// and falls by two while it does not. A genuinely busy CPU still reaches the
/// threshold; a spiky one never does, because the decay outruns it.
@MainActor
final class AlertCenter: ObservableObject {

    // MARK: - Public state

    /// Sorted most severe first, then in rule order, so rows never jump around
    /// between polls. Only republished when the content genuinely changes.
    @Published private(set) var active: [ActiveAlert] = []

    /// Master switch for notifications. The alerts themselves keep working when
    /// this is off — the dashboard still shows them, they just stay quiet.
    @Published var notificationsEnabled: Bool { didSet { persistMaster() } }

    /// The app delegate connects this to dashboard routing after the window
    /// controller exists. Notification delivery remains useful without it.
    var onOpenAlert: ((AlertRuleID) -> Void)? {
        didSet { presenter.onOpenAlert = onOpenAlert }
    }

    static let allRules: [AlertRuleInfo] = rules.map(\.info)

    // MARK: - Private state

    /// Published so the settings pane redraws when a switch is flipped, private
    /// because the only supported way in is `isEnabled` / `binding(for:)`.
    @Published private var disabledRules: Set<AlertRuleID> = []
    @Published private var snoozedUntil: [AlertRuleID: Date] = [:]

    /// Not published: nothing in the UI shows it, so a change here should not
    /// invalidate a view.
    private var lastNotified: [AlertRuleID: Date] = [:]

    private var states: [AlertRuleID: RuleState] = [:]
    private var evaluations: [AlertRuleID: Evaluation] = [:]

    private let defaults: UserDefaults
    private let log = Logger(subsystem: "com.paulomateus.vitality", category: "alerts")
    private var cancellable: AnyCancellable?

    /// Both windows are six hours: long enough that a machine that stays at 92%
    /// full all week notifies once a day rather than once a poll, short enough
    /// that a problem you ignored this morning is raised again tonight.
    private static let snoozeInterval: TimeInterval = 6 * 3600
    private static let notificationCooldown: TimeInterval = 6 * 3600

    /// macOS suppresses banners for the frontmost app unless a delegate opts
    /// in — and Vitality is frontmost exactly when the dashboard is open, which
    /// is when someone is watching a hot CPU wait out its sustain window.
    private final class ForegroundPresenter: NSObject, UNUserNotificationCenterDelegate {
        var onOpenAlert: ((AlertRuleID) -> Void)?

        func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    willPresent notification: UNNotification,
                                    withCompletionHandler completionHandler:
                                        @escaping (UNNotificationPresentationOptions) -> Void) {
            completionHandler([.banner, .sound])
        }

        func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    didReceive response: UNNotificationResponse,
                                    withCompletionHandler completionHandler: @escaping () -> Void) {
            defer { completionHandler() }
            guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
                  let raw = response.notification.request.content.userInfo["rule"] as? String,
                  let rule = AlertRuleID(rawValue: raw) else { return }
            let open = onOpenAlert
            DispatchQueue.main.async { open?(rule) }
        }
    }

    private let presenter = ForegroundPresenter()

    init(poller: StatusPoller) {
        self.defaults = .standard
        notificationsEnabled = defaults.object(forKey: Key.master) as? Bool ?? true
        loadPerRuleSettings()

        UNUserNotificationCenter.current().delegate = presenter

        cancellable = poller.$latest.sink { [weak self] status in
            self?.ingest(status)
        }
    }

    // MARK: - Per-rule settings

    func isEnabled(_ rule: AlertRuleID) -> Bool {
        !disabledRules.contains(rule)
    }

    func binding(for rule: AlertRuleID) -> Binding<Bool> {
        Binding(
            get: { self.isEnabled(rule) },
            set: { isOn in
                if isOn { self.disabledRules.remove(rule) } else { self.disabledRules.insert(rule) }
                self.persist(rule)
                // A rule switched off has to leave the list now, not on the
                // next poll — the user is looking straight at it.
                self.rebuildActive()
            }
        )
    }

    /// Hides the alert and silences the rule for six hours. The rule keeps being
    /// evaluated underneath: when the snooze lapses, what comes back is the
    /// truth about the machine now, not a replay of what was dismissed.
    func snooze(_ rule: AlertRuleID) {
        snoozedUntil[rule] = Date().addingTimeInterval(Self.snoozeInterval)
        persist(rule)
        rebuildActive()
    }

    private func isSnoozed(_ rule: AlertRuleID) -> Bool {
        guard let until = snoozedUntil[rule] else { return false }
        return until > Date()
    }

    /// A rule that is off or snoozed is invisible *and* silent — one predicate,
    /// so the two can never disagree.
    private func isMuted(_ rule: AlertRuleID) -> Bool {
        !isEnabled(rule) || isSnoozed(rule)
    }

    // MARK: - Evaluation

    private func ingest(_ status: SystemStatus?) {
        guard let status else { return }

        var justFired: [(rule: Rule, title: String, detail: String)] = []

        for rule in Self.rules {
            let id = rule.info.id
            let evaluation = rule.evaluate(status)
            var state = states[id] ?? RuleState()
            let wasFiring = state.isFiring

            switch evaluation {
            case .triggering:
                // Saturating at `sustain` matters: without it a CPU pinned for
                // an hour would bank 3,600 counts and take half an hour of
                // decay to admit the load had ended.
                state.counter = min(state.counter + 1, rule.sustain)
                if state.counter >= rule.sustain { state.isFiring = true }
            case .holding:
                // Inside the hysteresis band. The condition no longer holds, so
                // the counter decays, but an alert already up stays up.
                state.counter = max(0, state.counter - 2)
            case .released:
                state.counter = max(0, state.counter - 2)
                state.isFiring = false
            }

            states[id] = state
            evaluations[id] = evaluation

            // First banner on the rising edge. A problem that stays true
            // (disk at 92% all week) is raised again once the cooldown lapses.
            if state.isFiring, let reading = evaluation.reading,
               !wasFiring || shouldRenotify(id) {
                justFired.append((rule, reading.title, reading.detail))
            }
        }

        rebuildActive()
        for fired in justFired {
            notifyIfAllowed(fired.rule, title: fired.title, detail: fired.detail)
        }
    }

    private func rebuildActive() {
        var alerts: [ActiveAlert] = []

        for rule in Self.rules {
            let id = rule.info.id
            guard states[id]?.isFiring == true, !isMuted(id) else { continue }
            guard let evaluation = evaluations[id],
                  let reading = evaluation.reading else { continue }
            alerts.append(ActiveAlert(
                id: id,
                severity: reading.severity,
                title: reading.title,
                detail: reading.detail,
                actionLabel: rule.actionLabel,
                action: rule.action
            ))
        }

        // Severity first, rule order second. `enumerated` gives the tiebreak
        // for free because `rules` is already in `allCases` order.
        alerts.sort { lhs, rhs in
            let left = Self.rank(lhs.severity), right = Self.rank(rhs.severity)
            if left != right { return left > right }
            return Self.order(lhs.id) < Self.order(rhs.id)
        }

        // The dashboard redraws its whole alert section on any change here, and
        // a steady 92%-full disk produces the identical list 3,600 times an
        // hour. Publishing only real changes keeps that free.
        let signature = alerts.map { "\($0.id.rawValue)|\(Self.rank($0.severity))|\($0.title)|\($0.detail)" }
        guard signature != activeSignature else { return }
        activeSignature = signature
        active = alerts
    }

    private var activeSignature: [String] = []

    private static func rank(_ level: Severity.Level) -> Int {
        switch level {
        case .normal:   return 0
        case .warning:  return 1
        case .critical: return 2
        }
    }

    private static func order(_ id: AlertRuleID) -> Int {
        AlertRuleID.allCases.firstIndex(of: id) ?? 0
    }

    // MARK: - Notifications

    private func shouldRenotify(_ id: AlertRuleID) -> Bool {
        guard let last = lastNotified[id] else { return true }
        return Date().timeIntervalSince(last) >= Self.notificationCooldown
    }

    private func notifyIfAllowed(_ rule: Rule, title: String, detail: String) {
        let id = rule.info.id
        guard notificationsEnabled, !isMuted(id) else { return }

        let now = Date()
        if let last = lastNotified[id], now.timeIntervalSince(last) < Self.notificationCooldown {
            return
        }

        // Everything the callbacks need is captured by value: `Logger` is
        // cheap and Sendable, so nothing has to hop back to the main actor
        // just to write a line to the log.
        let log = log
        let identifier = "\(id.rawValue)-\(now.timeIntervalSince1970)"

        // Authorisation is asked for on the first banner rather than at launch:
        // a monitor that demands notification permission before it has anything
        // to say is a prompt the user has no reason to grant. Repeat calls are
        // free — the system shows the sheet once and replays the answer after.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            guard granted else {
                // Denied is a legitimate answer, not a failure: the dashboard
                // still shows the alert, so nothing is lost by staying quiet.
                log.info("notification suppressed: \(error?.localizedDescription ?? "not authorised", privacy: .public)")
                return
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = detail
            content.sound = .default
            content.userInfo = ["rule": id.rawValue]
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { [weak self] addError in
                if let addError {
                    log.error("notification failed: \(addError.localizedDescription, privacy: .public)")
                    return
                }
                // The cooldown starts only once a notification was actually
                // handed to the system. Stamping up front burned the six-hour
                // window on banners that never appeared — most visibly the
                // very first alert, while the authorisation sheet was still
                // on screen undecided.
                Task { @MainActor in self?.markNotified(id, at: now) }
            }
        }
    }

    private func markNotified(_ id: AlertRuleID, at date: Date) {
        lastNotified[id] = date
        persist(id)
    }

    // MARK: - Persistence

    private enum Key {
        static let master = "alerts.notificationsEnabled"
        static func enabled(_ id: AlertRuleID) -> String { "alerts.rule.\(id.rawValue).enabled" }
        static func snooze(_ id: AlertRuleID) -> String { "alerts.rule.\(id.rawValue).snoozedUntil" }
        static func notified(_ id: AlertRuleID) -> String { "alerts.rule.\(id.rawValue).lastNotified" }
    }

    private func loadPerRuleSettings() {
        for id in AlertRuleID.allCases {
            // Absent means on: a new rule shipped in an update starts watching
            // rather than waiting to be discovered in a settings pane.
            if defaults.object(forKey: Key.enabled(id)) as? Bool == false {
                disabledRules.insert(id)
            }
            snoozedUntil[id] = defaults.object(forKey: Key.snooze(id)) as? Date
            lastNotified[id] = defaults.object(forKey: Key.notified(id)) as? Date
        }
    }

    private func persistMaster() {
        defaults.set(notificationsEnabled, forKey: Key.master)
    }

    private func persist(_ id: AlertRuleID) {
        defaults.set(isEnabled(id), forKey: Key.enabled(id))
        defaults.set(snoozedUntil[id], forKey: Key.snooze(id))
        defaults.set(lastNotified[id], forKey: Key.notified(id))
    }

    // MARK: - Rule table

    private struct RuleState {
        var counter = 0
        var isFiring = false
    }

    /// What a rule makes of one snapshot.
    ///
    /// `holding` is the hysteresis band — past the release threshold but short
    /// of the firing one. It sustains an alert that is already up and starts
    /// nothing new.
    private enum Evaluation {
        case triggering(Severity.Level, title: String, detail: String)
        case holding(Severity.Level, title: String, detail: String)
        case released

        var reading: (severity: Severity.Level, title: String, detail: String)? {
            switch self {
            case let .triggering(severity, title, detail): return (severity, title, detail)
            case let .holding(severity, title, detail):    return (severity, title, detail)
            case .released:                                return nil
            }
        }
    }

    /// One rule per row, evaluated by the same loop. Thresholds live here and
    /// only here, so "what makes Vitality shout" is a table you can read in one
    /// screen rather than five branches scattered through the poll handler.
    private struct Rule {
        let info: AlertRuleInfo
        let action: AlertAction
        let actionLabel: String?
        /// Polls the condition must hold before firing. The poller runs at 1 Hz,
        /// so this reads as seconds. `1` fires on the first reading.
        let sustain: Int
        let evaluate: (SystemStatus) -> Evaluation
    }

    private static let rules: [Rule] = [
        Rule(
            info: AlertRuleInfo(
                id: .diskFull,
                title: "Disk almost full",
                detail: "90% used",
                icon: "externaldrive.fill"
            ),
            action: .openStorage,
            actionLabel: "Review storage",
            // A disk does not flap. It fills over weeks and empties in one
            // deliberate action, so there is nothing to wait out.
            sustain: 1,
            evaluate: { status in
                guard let disk = status.primaryDisk, let used = disk.usedPercent else { return .released }
                let detail = "Only " + Fmt.bytes(disk.free) + " is left on " + disk.displayName + "."
                if used >= 95 { return .triggering(.critical, title: "Disk critically full", detail: detail) }
                if used >= 90 { return .triggering(.warning, title: "Disk almost full", detail: detail) }
                if used >= 88 { return .holding(.warning, title: "Disk almost full", detail: detail) }
                return .released
            }
        ),
        Rule(
            info: AlertRuleInfo(
                id: .cpuSustained,
                title: "CPU pinned",
                detail: "90% for 2 minutes",
                icon: "cpu"
            ),
            action: .openActivity,
            actionLabel: "Inspect activity",
            sustain: 120,
            evaluate: { status in
                guard let usage = status.cpu?.usage else { return .released }
                // The busiest process is the whole reason to open Activity, so
                // it goes in the line the user actually reads.
                let blame = status.topProcess?.name.map { " " + $0 + " is the busiest process." } ?? ""
                let detail = "The CPU has been at " + Fmt.percent(usage) + " for the last two minutes." + blame
                if usage >= 95 { return .triggering(.critical, title: "CPU pinned at full load", detail: detail) }
                if usage >= 90 { return .triggering(.warning, title: "CPU load is sustained", detail: detail) }
                if usage >= 75 { return .holding(.warning, title: "CPU load is sustained", detail: detail) }
                return .released
            }
        ),
        Rule(
            info: AlertRuleInfo(
                id: .swapHeavy,
                title: "Swap under pressure",
                detail: "75% of swap for 1 minute",
                icon: "memorychip"
            ),
            action: .openActivity,
            actionLabel: "Inspect activity",
            sustain: 60,
            evaluate: { status in
                guard let memory = status.memory,
                      let used = memory.swapUsed,
                      let total = memory.swapTotal,
                      total > 0 else { return .released }
                let ratio = Double(used) / Double(total)
                let detail = "Your Mac is using " + Fmt.bytes(used) + " of " + Fmt.bytes(total)
                    + " of swap. Quitting a heavy app may help."
                if ratio >= 0.75 { return .triggering(.warning, title: "Memory pressure is high", detail: detail) }
                if ratio >= 0.60 { return .holding(.warning, title: "Memory pressure is high", detail: detail) }
                return .released
            }
        ),
        Rule(
            info: AlertRuleInfo(
                id: .tempHigh,
                title: "CPU running hot",
                detail: "95° for 30 seconds",
                icon: "thermometer.high"
            ),
            action: .openSensors,
            actionLabel: "View sensors",
            // Half a minute filters the fan-spin-up spikes that a video export
            // produces on the way to a perfectly healthy steady state.
            sustain: 30,
            evaluate: { status in
                guard let celsius = status.thermal?.cpu else { return .released }
                let detail = "The CPU cluster has been averaging " + Fmt.celsius(celsius, decimals: 1)
                    + ". Sustained heat means the machine is throttling."
                if celsius >= 95 { return .triggering(.critical, title: "CPU is running hot", detail: detail) }
                if celsius >= 88 { return .holding(.critical, title: "CPU is running hot", detail: detail) }
                return .released
            }
        ),
        Rule(
            info: AlertRuleInfo(
                id: .batteryLow,
                title: "Battery low",
                detail: "10% on battery power",
                icon: "battery.25"
            ),
            action: .openPower,
            actionLabel: "Review power",
            // Nothing to wait for: the charge is already reported as a smoothed
            // integer, and the user needs the cable now, not in two minutes.
            sustain: 1,
            evaluate: { status in
                guard let battery = status.battery, let percent = battery.percent else { return .released }
                // Plugging in ends the alert outright — the number climbing
                // back past 15% is beside the point once power is coming in.
                if status.power?.isOnAC == true { return .released }
                let remaining = battery.timeLeft.map { " About " + $0 + " remaining." } ?? ""
                let detail = "\(percent)% left and running on battery." + remaining
                if percent <= 5 { return .triggering(.critical, title: "Battery critically low", detail: detail) }
                if percent <= 10 { return .triggering(.warning, title: "Battery low", detail: detail) }
                if percent <= 15 { return .holding(.warning, title: "Battery low", detail: detail) }
                return .released
            }
        )
    ]
}
