import Foundation

enum AppGroup {
    /// The App Group identifier, injected at build time from `DEVELOPMENT_TEAM`
    /// via the `VitalityAppGroup` Info.plist key.
    ///
    /// macOS requires App Group identifiers to be **prefixed with the team ID**
    /// (`TEAMID.group.example.app`). The bare `group.*` form is the iOS
    /// convention; on macOS group containers are TCC-protected and
    /// containermanagerd rejects any requestor whose code signature doesn't
    /// match that prefix — with a permission error on write that looks nothing
    /// like a naming problem.
    ///
    /// Read from Info.plist rather than hardcoded so the repo carries no
    /// individual's team ID and still builds for anyone who clones it.
    static let id: String = {
        let value = Bundle.main.object(forInfoDictionaryKey: "VitalityAppGroup") as? String
        guard let value, !value.isEmpty, !value.hasPrefix("$(") else {
            assertionFailure("VitalityAppGroup missing from Info.plist — set DEVELOPMENT_TEAM in Local.xcconfig")
            return ""
        }
        return value
    }()
}

enum SharedStatusStore {
    private static var containerURL: URL? {
        guard !AppGroup.id.isEmpty else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id)
    }

    private static var statusFileURL: URL? {
        containerURL?.appendingPathComponent("status.json")
    }

    @discardableResult
    static func write(_ status: SystemStatus) -> Error? {
        guard let container = containerURL, let url = statusFileURL else {
            return NSError(domain: "SharedStatusStore", code: 1, userInfo: [
                NSLocalizedDescriptionKey:
                    "No container for app group “\(AppGroup.id)”. Check DEVELOPMENT_TEAM and the app group entitlement."
            ])
        }

        do {
            // The container normally exists already, but creating it here means
            // a first run doesn't fail just because provisioning lagged.
            try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(status)
            // Atomic so the widget never reads a half-written file.
            try data.write(to: url, options: .atomic)
            return nil
        } catch {
            return error
        }
    }

    static func read() -> SystemStatus? {
        guard let url = statusFileURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SystemStatus.self, from: data)
    }
}
