import Foundation
import JavaScriptCore
import UIKit

// Implements Loom.device — synchronous device info, no permissions required.
final class DeviceBridge {
    private let ctx: JSContext

    nonisolated init(ctx: JSContext) {
        self.ctx = ctx
    }

    nonisolated func makeObject() -> JSValue {
        let obj = JSValue(newObjectIn: ctx)!

        // All UIDevice reads must happen on main thread.
        var batteryLevel: Float = 0
        var isCharging = false
        var model = ""
        var systemVersion = ""

        DispatchQueue.main.sync {
            let dev = UIDevice.current
            dev.isBatteryMonitoringEnabled = true
            batteryLevel = dev.batteryLevel          // -1 if unknown
            isCharging = dev.batteryState == .charging || dev.batteryState == .full
            model = dev.model
            systemVersion = dev.systemVersion
        }

        let info: [String: Any] = [
            "batteryLevel":   batteryLevel < 0 ? NSNull() : batteryLevel,
            "isCharging":     isCharging,
            "model":          model,
            "systemVersion":  systemVersion,
        ]
        return JSValue(object: info as NSDictionary, in: ctx) ?? JSValue(undefinedIn: ctx)
    }
}
