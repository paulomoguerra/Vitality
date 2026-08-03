import Foundation

enum StatusCollector {
    static func collect() -> Result<SystemStatus, MoleError> {
        MoleCLI.decode(SystemStatus.self, from: ["status", "--json"], timeout: 15)
    }
}
