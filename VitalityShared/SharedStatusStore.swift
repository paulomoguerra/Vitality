import Foundation

enum AppGroup {
    static let id = "group.com.paulomateus.vitality"
}

enum SharedStatusStore {
    private static var statusFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id)?
            .appendingPathComponent("status.json")
    }

    @discardableResult
    static func write(_ status: SystemStatus) -> Error? {
        guard let url = statusFileURL else {
            return NSError(domain: "SharedStatusStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "containerURL is nil"])
        }
        guard let data = try? JSONEncoder().encode(status) else {
            return NSError(domain: "SharedStatusStore", code: 2, userInfo: [NSLocalizedDescriptionKey: "encode failed"])
        }
        do {
            try data.write(to: url)
            return nil
        } catch {
            return error
        }
    }

    static func read() -> SystemStatus? {
        guard let url = statusFileURL else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SystemStatus.self, from: data)
    }
}
