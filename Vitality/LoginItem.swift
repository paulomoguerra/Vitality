import Foundation
import ServiceManagement

enum LoginItem {
    static func register() {
        do {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Vitality: failed to register login item: \(error)")
        }
    }
}
