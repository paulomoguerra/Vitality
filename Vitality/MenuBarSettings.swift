import Combine
import SwiftUI

/// When Vitality is allowed to spend colour in the menu bar.
enum MenuBarColorMode: String, CaseIterable, Identifiable {
    case warnings, always, monochrome

    var id: String { rawValue }

    var title: String {
        switch self {
        case .warnings:   return "When it matters"
        case .always:     return "Always"
        case .monochrome: return "Never"
        }
    }
}

/// Menu bar and startup preferences, persisted in `UserDefaults`.
///
/// Deliberately not `@AppStorage`: the metric selection is a set, `@AppStorage`
/// only speaks the property-list primitives, and scattering seven booleans
/// across defaults keys would make "which metrics are on" impossible to read
/// as one value.
@MainActor
final class MenuBarSettings: ObservableObject {

    private enum Key {
        static let metrics = "menuBar.metrics"
        static let showsLabels = "menuBar.showsLabels"
        static let colorMode = "menuBar.colorMode"
        static let showsGraph = "menuBar.showsGraph"
        static let showsAppIcon = "menuBar.showsAppIcon"
        static let launchAtLogin = "menuBar.launchAtLogin"
    }

    @Published var metrics: Set<MenuBarMetric> { didSet { save() } }
    @Published var showsLabels: Bool { didSet { save() } }
    @Published var colorMode: MenuBarColorMode { didSet { save() } }
    @Published var showsGraph: Bool { didSet { save() } }
    @Published var showsAppIcon: Bool { didSet { save() } }
    /// Defaults to the previous first-launch behaviour; a false value is
    /// persisted so an explicit opt-out is not undone on the next launch.
    @Published var launchAtLogin: Bool { didSet { save() } }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let stored = defaults.array(forKey: Key.metrics) as? [String] {
            metrics = Set(stored.compactMap(MenuBarMetric.init(rawValue:)))
        } else {
            // First launch shows the feature rather than hiding it behind a
            // settings pane nobody knows exists.
            metrics = [.cpu, .gpu, .memory]
        }

        showsLabels = defaults.object(forKey: Key.showsLabels) as? Bool ?? true
        colorMode = defaults.string(forKey: Key.colorMode)
            .flatMap(MenuBarColorMode.init(rawValue:)) ?? .warnings
        showsGraph = defaults.object(forKey: Key.showsGraph) as? Bool ?? false
        showsAppIcon = defaults.object(forKey: Key.showsAppIcon) as? Bool ?? true
        launchAtLogin = defaults.object(forKey: Key.launchAtLogin) as? Bool ?? true
    }

    /// Selected metrics in canonical order.
    var displayedMetrics: [MenuBarMetric] {
        MenuBarMetric.allCases.filter(metrics.contains)
    }

    /// Turning off every metric *and* the icon would leave a zero-width status
    /// item — the app still running, with nothing left to click to get it back.
    /// The icon wins that argument.
    var showsAppIconEffective: Bool {
        showsAppIcon || metrics.isEmpty
    }

    func binding(for metric: MenuBarMetric) -> Binding<Bool> {
        Binding(
            get: { self.metrics.contains(metric) },
            set: { isOn in
                if isOn { self.metrics.insert(metric) } else { self.metrics.remove(metric) }
            }
        )
    }

    /// The colour a reading should be drawn in, or `nil` to inherit the menu
    /// bar's own foreground colour.
    func tint(for level: Severity.Level?) -> Color? {
        guard let level else { return nil }
        switch colorMode {
        case .monochrome: return nil
        case .always:     return level.color
        case .warnings:   return level == .normal ? nil : level.color
        }
    }

    private func save() {
        defaults.set(displayedMetrics.map(\.rawValue), forKey: Key.metrics)
        defaults.set(showsLabels, forKey: Key.showsLabels)
        defaults.set(colorMode.rawValue, forKey: Key.colorMode)
        defaults.set(showsGraph, forKey: Key.showsGraph)
        defaults.set(showsAppIcon, forKey: Key.showsAppIcon)
        defaults.set(launchAtLogin, forKey: Key.launchAtLogin)
    }
}
