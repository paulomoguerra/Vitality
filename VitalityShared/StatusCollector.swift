import Foundation

enum StatusCollector {
    private static let candidatePaths = [
        "/opt/homebrew/bin/mo",
        "/usr/local/bin/mo",
    ]

    static func collect() -> SystemStatus? {
        for path in candidatePaths where FileManager.default.isExecutableFile(atPath: path) {
            if let status = run(at: path) {
                return status
            }
        }
        return nil
    }

    private static func run(at path: String) -> SystemStatus? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["status", "--json"]

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return try? JSONDecoder().decode(SystemStatus.self, from: data)
    }
}
