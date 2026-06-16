import Foundation
import JavaScriptCore
import EventKit

// Implements Loom.calendar.events.* and Loom.calendar.reminders.*
final class CalendarBridge {
    private let ctx: JSContext
    private let store = EKEventStore()
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated init(ctx: JSContext) {
        self.ctx = ctx
    }

    nonisolated func makeObject() -> JSValue {
        let obj = JSValue(newObjectIn: ctx)!
        obj.setObject(makeEventsObject(),    forKeyedSubscript: "events"    as NSString)
        obj.setObject(makeRemindersObject(), forKeyedSubscript: "reminders" as NSString)
        return obj
    }

    nonisolated private func makeEventsObject() -> JSValue {
        let obj = JSValue(newObjectIn: ctx)!
        let capturedCtx = ctx

        let listBlock: @convention(block) (JSValue) -> JSValue = { [weak self] optsVal in
            guard let self else { return JSValue(undefinedIn: capturedCtx) }
            let opts = optsVal.toDictionary() as? [String: Any] ?? [:]
            let from = (opts["from"] as? String).flatMap { self.iso.date(from: $0) } ?? Date()
            let to   = (opts["to"]   as? String).flatMap { self.iso.date(from: $0) } ?? Date().addingTimeInterval(7 * 86400)
            return self.makePromise { resolve, reject in
                self.requestEventAccess { granted, error in
                    if let error { reject(error.localizedDescription); return }
                    guard granted else { reject("Calendar permission denied"); return }
                    let pred = self.store.predicateForEvents(withStart: from, end: to, calendars: nil)
                    let events = self.store.events(matching: pred).map { self.eventDict($0) }
                    resolve(events as NSArray)
                }
            }
        }

        let createBlock: @convention(block) (JSValue) -> JSValue = { [weak self] optsVal in
            guard let self else { return JSValue(undefinedIn: capturedCtx) }
            let opts = optsVal.toDictionary() as? [String: Any] ?? [:]
            return self.makePromise { resolve, reject in
                self.requestEventAccess { granted, error in
                    if let error { reject(error.localizedDescription); return }
                    guard granted else { reject("Calendar permission denied"); return }
                    let event = EKEvent(eventStore: self.store)
                    event.calendar = self.store.defaultCalendarForNewEvents
                    self.applyEventFields(opts, to: event)
                    do { try self.store.save(event, span: .thisEvent); resolve(["id": event.eventIdentifier ?? ""] as NSDictionary) }
                    catch { reject(error.localizedDescription) }
                }
            }
        }

        let updateBlock: @convention(block) (JSValue, JSValue) -> JSValue = { [weak self] idVal, optsVal in
            guard let self else { return JSValue(undefinedIn: capturedCtx) }
            let id = idVal.toString() ?? ""
            let opts = optsVal.toDictionary() as? [String: Any] ?? [:]
            return self.makePromise { resolve, reject in
                self.requestEventAccess { granted, error in
                    if let error { reject(error.localizedDescription); return }
                    guard granted else { reject("Calendar permission denied"); return }
                    guard let event = self.store.event(withIdentifier: id) else {
                        reject("Event not found: \(id)"); return
                    }
                    self.applyEventFields(opts, to: event)
                    do { try self.store.save(event, span: .thisEvent); resolve(nil) }
                    catch { reject(error.localizedDescription) }
                }
            }
        }

        let deleteBlock: @convention(block) (JSValue) -> JSValue = { [weak self] idVal in
            guard let self else { return JSValue(undefinedIn: capturedCtx) }
            let id = idVal.toString() ?? ""
            return self.makePromise { resolve, reject in
                self.requestEventAccess { granted, error in
                    if let error { reject(error.localizedDescription); return }
                    guard granted else { reject("Calendar permission denied"); return }
                    guard let event = self.store.event(withIdentifier: id) else {
                        reject("Event not found: \(id)"); return
                    }
                    do { try self.store.remove(event, span: .thisEvent); resolve(nil) }
                    catch { reject(error.localizedDescription) }
                }
            }
        }

        obj.setObject(listBlock,   forKeyedSubscript: "list"   as NSString)
        obj.setObject(createBlock, forKeyedSubscript: "create" as NSString)
        obj.setObject(updateBlock, forKeyedSubscript: "update" as NSString)
        obj.setObject(deleteBlock, forKeyedSubscript: "delete" as NSString)
        return obj
    }

    nonisolated private func makeRemindersObject() -> JSValue {
        let obj = JSValue(newObjectIn: ctx)!
        let capturedCtx = ctx

        let createBlock: @convention(block) (JSValue) -> JSValue = { [weak self] optsVal in
            guard let self else { return JSValue(undefinedIn: capturedCtx) }
            let opts = optsVal.toDictionary() as? [String: Any] ?? [:]
            return self.makePromise { resolve, reject in
                self.requestReminderAccess { granted, error in
                    if let error { reject(error.localizedDescription); return }
                    guard granted else { reject("Reminders permission denied"); return }
                    let reminder = EKReminder(eventStore: self.store)
                    reminder.calendar = self.store.defaultCalendarForNewReminders()
                    if let title = opts["title"] as? String { reminder.title = title }
                    if let due = (opts["dueDate"] as? String).flatMap({ self.iso.date(from: $0) }) {
                        reminder.dueDateComponents = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute], from: due)
                    }
                    do { try self.store.save(reminder, commit: true); resolve(["id": reminder.calendarItemIdentifier] as NSDictionary) }
                    catch { reject(error.localizedDescription) }
                }
            }
        }

        obj.setObject(createBlock, forKeyedSubscript: "create" as NSString)
        return obj
    }

    private func requestEventAccess(completion: @escaping (Bool, Error?) -> Void) {
        store.requestFullAccessToEvents(completion: completion)
    }

    private func requestReminderAccess(completion: @escaping (Bool, Error?) -> Void) {
        store.requestFullAccessToReminders(completion: completion)
    }

    private func eventDict(_ e: EKEvent) -> [String: Any] {
        [
            "id":       e.eventIdentifier ?? "",
            "title":    e.title ?? "",
            "start":    iso.string(from: e.startDate),
            "end":      iso.string(from: e.endDate),
            "allDay":   e.isAllDay,
            "calendar": e.calendar?.title ?? "",
            "notes":    e.notes ?? "",
        ]
    }

    private func applyEventFields(_ opts: [String: Any], to event: EKEvent) {
        if let v = opts["title"] as? String { event.title = v }
        if let v = (opts["start"] as? String).flatMap({ iso.date(from: $0) }) { event.startDate = v }
        if let v = (opts["end"]   as? String).flatMap({ iso.date(from: $0) }) { event.endDate   = v }
        if let v = opts["notes"]  as? String { event.notes = v }
        if event.endDate == nil, let s = event.startDate { event.endDate = s.addingTimeInterval(3600) }
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
