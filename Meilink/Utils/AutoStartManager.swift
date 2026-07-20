import Foundation
import ServiceManagement

struct AutoStartManager {
    static func enableAutoStart() throws {
        try SMAppService.mainApp.register()
    }

    static func disableAutoStart() throws {
        try SMAppService.mainApp.unregister()
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func toggle() throws {
        if isEnabled {
            try disableAutoStart()
        } else {
            try enableAutoStart()
        }
    }
}
