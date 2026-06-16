import Foundation
import JavaScriptCore
import UserNotifications

// Implements Loom.notify.schedule({ title, body, trigger: { date } })
final class NotifyBridge {
    private let ctx: JSContext
    private let project: LoomProject
    private let runLoop: CFRunLoop

    nonisolated init(ctx: JSContext, project: LoomProject, runLoop: CFRunLoop) {
        self.ctx = ctx
        self.project = project
        self.runLoop = runLoop
    }

    nonisolated func makeObject() -> JSValue {
        let obj = JSValue(newObjectIn: ctx)!

        let scheduleBlock: @convention(block) (JSValue) -> JSValue = { [weak self] optsVal in
            guard let self else { return JSValue(undefinedIn: optsVal.context) }
            let opts    = optsVal.toDictionary() as? [String: Any] ?? [:]
            let title   = opts["title"] as? String ?? ""
            let body    = opts["body"]  as? String ?? ""
            let trigger = opts["trigger"] as? [String: Any]
            let dateStr = trigger?["date"] as? String ?? ""

            return self.makePromise { resolve, reject in
                let center = UNUserNotificationCenter.current()
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if let error { reject(error.localizedDescription); return }
                    guard granted else { reject("Notification permission denied"); return }

                    let content = UNMutableNotificationContent()
                    content.title = title
                    content.body  = body
                    content.sound = .default

                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    let date = formatter.date(from: dateStr) ?? Date().addingTimeInterval(5)
                    let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
                    let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

                    let id = "\(self.project.name)-\(UUID().uuidString)"
                    let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                    center.add(request) { error in
                        if let error { reject(error.localizedDescription) }
                        else { resolve(id) }
                    }
                }
            }
        }

        obj.setObject(scheduleBlock, forKeyedSubscript: "schedule" as NSString)
        return obj
    }

    nonisolated private func makePromise(
        _ executor: (_ resolve: @escaping (Any?) -> Void, _ reject: @escaping (String) -> Void) -> Void
    ) -> JSValue {
        var resolvedVal: Any? = nil
        var rejectMsg: String? = nil
        let sema = DispatchSemaphore(value: 0)
        executor(
            { val in resolvedVal = val; sema.signal() },
            { msg in rejectMsg = msg; sema.signal() }
        )
        sema.wait()
        if let msg = rejectMsg {
            return ctx.objectForKeyedSubscript("__loomReject")?
                .call(withArguments: [msg]) ?? JSValue(undefinedIn: ctx)
        } else if let v = resolvedVal {
            return ctx.objectForKeyedSubscript("__loomResolve")?
                .call(withArguments: [v]) ?? JSValue(undefinedIn: ctx)
        } else {
            return ctx.objectForKeyedSubscript("__loomResolve")?
                .call(withArguments: []) ?? JSValue(undefinedIn: ctx)
        }
    }
}
