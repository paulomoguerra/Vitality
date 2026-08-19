import Foundation
import ServiceManagement

enum LoginItem {
    static func apply(enabled: Bool) {
        let service = SMAppService.mainApp

        do {
            switch (enabled, service.status) {
            case (true, .notRegistered):
                try service.register()
            case (false, .enabled):
                try service.unregister()
            default:
                // An enabled item is already configured. Likewise, do not
                // retry a pending approval on every app launch.
                break
            }
        } catch {
            let action = enabled ? "enable" : "disable"
            NSLog("Vitality: failed to \(action) login item: \(error)")
        }
    }
}
