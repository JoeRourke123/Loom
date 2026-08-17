import ActivityKit
import Foundation
import JavaScriptCore

// Implements Loom.activity — Live Activities driven from a script.
//
//   await Loom.activity.start({ key, content, compactLeading, …, staleAfter, relevance, style })
//   await Loom.activity.update(key, { content, …, alert: { title, body } })
//   await Loom.activity.end(key, { content, dismiss: 'immediate' | 'default' | <seconds> })
//   await Loom.activity.list()
//
// Layouts are ordinary w.* trees, the same builders widgets use, serialised into the activity's
// ContentState and rendered natively by LoomLiveActivity.
//
// Two failure modes, kept deliberately distinct:
//   - script's fault (no key, oversized layout) → the promise rejects, because the script can fix it
//   - environment's refusal (no foreground, permission off, system limit) → warn and resolve null,
//     matching how Loom.ui degrades on a background run
final class ActivityBridge {
    private let ctx: JSContext
    private let project: LoomProject
    private let session: RunSession

    nonisolated init(ctx: JSContext, project: LoomProject, session: RunSession) {
        self.ctx = ctx
        self.project = project
        self.session = session
    }

    nonisolated func makeObject() -> JSValue {
        let obj = JSValue(newObjectIn: ctx)!
        let capturedCtx = ctx

        // start(opts) → Promise<string | null> — resolves the key, or null if iOS declined.
        let startBlock: @convention(block) (JSValue) -> JSValue = { [weak self] optsVal in
            guard let self else { return JSValue(undefinedIn: capturedCtx) }
            let opts = optsVal.isObject ? (optsVal.toDictionary() as? [String: Any] ?? [:]) : [:]
            let key = opts["key"] as? String ?? ""
            let layout = self.layoutJSON(from: optsVal)

            return self.makePromise { resolve, reject in
                guard !key.isEmpty else {
                    reject("Loom.activity.start: a `key` is required — it's how later runs find this activity to update or end it.")
                    return
                }
                if let tooBig = self.oversizeMessage(layout, api: "start") { reject(tooBig); return }

                Task { @MainActor in
                    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                        self.warn("Loom.activity.start skipped — Live Activities are turned off for Loom in Settings → Loom → Live Activities.")
                        resolve(NSNull())
                        return
                    }
                    do {
                        _ = try Activity<LoomActivityAttributes>.request(
                            attributes: LoomActivityAttributes(key: key, projectName: self.project.name),
                            content: self.content(layout: layout, opts: opts),
                            pushType: nil,
                            style: (opts["style"] as? String) == "transient" ? .transient : .standard
                        )
                        resolve(key)
                    } catch {
                        // `.visibility` means the run had no privilege to start one. A foreground
                        // run has it; so does a Shortcut or Siri run, because RunScriptIntent is a
                        // LiveActivityIntent and the system performs it on the user's behalf. What
                        // is left is an unattended wake-up — a background refresh — where iOS
                        // refuses with no workaround short of a push server. Updates and ends have
                        // no such restriction, so a background run can still drive an activity a
                        // foreground or Shortcut run began.
                        self.warn("Loom.activity.start('\(key)') skipped — \(error.localizedDescription)")
                        resolve(NSNull())
                    }
                }
            }
        }

        // update(key, opts) → Promise<bool> — false when no activity with that key is running.
        let updateBlock: @convention(block) (JSValue, JSValue) -> JSValue = { [weak self] keyVal, optsVal in
            guard let self else { return JSValue(undefinedIn: capturedCtx) }
            let key = keyVal.toString() ?? ""
            let opts = optsVal.isObject ? (optsVal.toDictionary() as? [String: Any] ?? [:]) : [:]
            let layout = self.layoutJSON(from: optsVal)

            return self.makePromise { resolve, reject in
                if let tooBig = self.oversizeMessage(layout, api: "update") { reject(tooBig); return }

                Task { @MainActor in
                    guard let activity = self.activity(for: key) else {
                        self.warn("Loom.activity.update('\(key)') skipped — no running activity with that key. It may have ended, or iOS may have expired it (activities last at most 8 hours).")
                        resolve(false)
                        return
                    }
                    await activity.update(
                        self.content(layout: layout, opts: opts),
                        alertConfiguration: self.alert(from: opts)
                    )
                    resolve(true)
                }
            }
        }

        // end(key, opts?) → Promise<bool>
        let endBlock: @convention(block) (JSValue, JSValue) -> JSValue = { [weak self] keyVal, optsVal in
            guard let self else { return JSValue(undefinedIn: capturedCtx) }
            let key = keyVal.toString() ?? ""
            let opts = optsVal.isObject ? (optsVal.toDictionary() as? [String: Any] ?? [:]) : [:]
            let layout = self.layoutJSON(from: optsVal)

            return self.makePromise { resolve, reject in
                if let tooBig = self.oversizeMessage(layout, api: "end") { reject(tooBig); return }

                Task { @MainActor in
                    guard let activity = self.activity(for: key) else {
                        self.warn("Loom.activity.end('\(key)') skipped — no running activity with that key.")
                        resolve(false)
                        return
                    }
                    // A nil final content keeps whatever is on screen; passing one lets a script
                    // leave a "done" state up during the dismissal window.
                    let final = layout.isEmpty ? nil : self.content(layout: layout, opts: opts)
                    await activity.end(final, dismissalPolicy: self.dismissal(from: opts))
                    resolve(true)
                }
            }
        }

        // list() → Promise<[{ key, state }]> — this project's running activities.
        let listBlock: @convention(block) () -> JSValue = { [weak self] in
            guard let self else { return JSValue(undefinedIn: capturedCtx) }
            return self.makePromise { resolve, _ in
                Task { @MainActor in
                    resolve(Activity<LoomActivityAttributes>.activities
                        .filter { $0.attributes.projectName == self.project.name }
                        .map { ["key": $0.attributes.key, "state": self.stateName($0.activityState)] })
                }
            }
        }

        obj.setObject(startBlock,  forKeyedSubscript: "start"  as NSString)
        obj.setObject(updateBlock, forKeyedSubscript: "update" as NSString)
        obj.setObject(endBlock,    forKeyedSubscript: "end"    as NSString)
        obj.setObject(listBlock,   forKeyedSubscript: "list"   as NSString)
        return obj
    }

    // MARK: - Layout

    // Copies just the presentation keys into a fresh object and stringifies it. Copying rather
    // than stringifying `opts` wholesale keeps staleAfter/relevance/alert/style out of the payload
    // — they're read natively, and every byte here counts against the 4 KB cap.
    //
    // JSON.stringify rather than JSONSerialization on toDictionary(): it coerces NaN and Infinity
    // to null instead of throwing, and it is the same serialiser the widget path already uses.
    private nonisolated func layoutJSON(from opts: JSValue) -> String {
        guard opts.isObject, let context = opts.context else { return "" }
        let layout = JSValue(newObjectIn: context)!
        for key in ["content", "compactLeading", "compactTrailing", "minimal", "expanded"] {
            guard let value = opts.objectForKeyedSubscript(key),
                  !value.isUndefined, !value.isNull else { continue }
            layout.setObject(value, forKeyedSubscript: key as NSString)
        }
        let json = context.objectForKeyedSubscript("JSON")?
            .objectForKeyedSubscript("stringify")?
            .call(withArguments: [layout])
        let text = json?.toString() ?? ""
        return (text == "undefined" || text == "{}") ? "" : text
    }

    private nonisolated func oversizeMessage(_ layout: String, api: String) -> String? {
        let bytes = layout.utf8.count
        guard bytes > LoomActivityAttributes.maxLayoutBytes else { return nil }
        return """
        Loom.activity.\(api): layout is \(bytes) bytes, over the \(LoomActivityAttributes.maxLayoutBytes) byte limit. \
        iOS caps a Live Activity's data at 4 KB. Trim the tree — fewer chart data points is usually the biggest win.
        """
    }

    private nonisolated func content(layout: String, opts: [String: Any]) -> ActivityContent<LoomActivityAttributes.ContentState> {
        ActivityContent(
            state: LoomActivityAttributes.ContentState(layout: layout),
            staleDate: (opts["staleAfter"] as? Double).map { Date(timeIntervalSinceNow: $0) },
            relevanceScore: opts["relevance"] as? Double ?? 0
        )
    }

    private nonisolated func alert(from opts: [String: Any]) -> AlertConfiguration? {
        guard let alert = opts["alert"] as? [String: Any] else { return nil }
        let title = alert["title"] as? String ?? ""
        let body  = alert["body"]  as? String ?? ""
        guard !title.isEmpty || !body.isEmpty else { return nil }
        return AlertConfiguration(
            title: LocalizedStringResource(stringLiteral: title),
            body: LocalizedStringResource(stringLiteral: body),
            sound: .default
        )
    }

    private nonisolated func dismissal(from opts: [String: Any]) -> ActivityUIDismissalPolicy {
        switch opts["dismiss"] {
        case let seconds as Double: return .after(Date(timeIntervalSinceNow: seconds))
        case "immediate" as String: return .immediate
        default:                    return .default
        }
    }

    // MARK: - Registry

    // Activity.activities is ActivityKit's own list of what's running, so it needs no backing
    // store of ours and can't go stale — an activity iOS expired simply isn't in it.
    @MainActor
    private func activity(for key: String) -> Activity<LoomActivityAttributes>? {
        Activity<LoomActivityAttributes>.activities.first {
            $0.attributes.key == key && $0.attributes.projectName == project.name
        }
    }

    private nonisolated func stateName(_ state: ActivityState) -> String {
        switch state {
        case .active:    return "active"
        case .ended:     return "ended"
        case .dismissed: return "dismissed"
        case .stale:     return "stale"
        case .pending:   return "pending"
        @unknown default: return "unknown"
        }
    }

    private nonisolated func warn(_ message: String) {
        session.append(LogEntry(
            runId: session.runId,
            projectName: project.name,
            level: .warn,
            message: message,
            data: nil
        ))
    }

    #if DEBUG
    // Round-trips a real JS opts object through layoutJSON and back out via LoomActivityLayout,
    // because that pair is a contract between two processes: a region that serialises under the
    // wrong key renders as nothing at all, with no error anywhere. Also pins the option coercions,
    // which arrive as NSNumber/NSString from JSC rather than as Swift types.
    static func runSelfCheck() -> Bool {
        var failures: [String] = []
        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            if !condition() { failures.append(name) }
        }

        let ctx = JSContext()!
        let bridge = ActivityBridge(
            ctx: ctx,
            project: LoomProject(name: "SelfCheck", folderURL: URL(fileURLWithPath: "/tmp")),
            session: RunSession(runId: UUID(), projectName: "SelfCheck", trigger: .manual)
        )

        let opts = ctx.evaluateScript("""
        ({
          key: 'k',
          content: { type: 'vstack', props: { background: 'blue' }, children: [
            { type: 'text', props: { content: 'Deploying' } }
          ]},
          compactLeading:  { type: 'icon', props: { name: 'shippingbox.fill' } },
          compactTrailing: { type: 'text', props: { content: '10%' } },
          minimal:         { type: 'icon', props: { name: 'shippingbox.fill' } },
          expanded: {
            leading: { type: 'text', props: { content: 'L' } },
            bottom:  { type: 'progressBar', props: { value: 0.1 } }
          },
          staleAfter: 900, relevance: 50, style: 'transient',
          alert: { title: 'T', body: 'B' }, dismiss: 'immediate'
        })
        """)!
        let json = bridge.layoutJSON(from: opts)

        // Non-presentation options must not reach the payload — every byte is charged against the
        // 4 KB cap, and these are all read natively.
        check("json.noStaleAfter", !json.contains("staleAfter"))
        check("json.noAlert", !json.contains("alert"))
        check("json.noKey", !json.contains("\"key\""))

        let layout = LoomActivityLayout.from(json: json)
        check("layout.decodes", layout != nil)
        check("layout.content", layout?.content?.type == "vstack")
        check("layout.contentChild", layout?.content?.children.first?.props["content"] as? String == "Deploying")
        check("layout.compactLeading", layout?.compactLeading?.props["name"] as? String == "shippingbox.fill")
        check("layout.compactTrailing", layout?.compactTrailing?.props["content"] as? String == "10%")
        check("layout.minimal", layout?.minimal?.type == "icon")
        check("layout.expandedLeading", layout?.expandedLeading?.props["content"] as? String == "L")
        check("layout.expandedBottom", layout?.expandedBottom?.type == "progressBar")
        // Absent regions must decode as nil, not as an empty node that renders a blank row.
        check("layout.expandedTrailingNil", layout?.expandedTrailing == nil)
        check("layout.expandedCenterNil", layout?.expandedCenter == nil)
        check("layout.tint", layout?.backgroundTintName == "blue")

        // JSC hands these over as NSNumber/NSString; a failed coercion here silently means
        // "no stale date" or "system default dismissal" rather than an error.
        let dict = opts.toDictionary() as? [String: Any] ?? [:]
        check("opts.staleAfter", bridge.content(layout: json, opts: dict).staleDate != nil)
        check("opts.relevance", bridge.content(layout: json, opts: dict).relevanceScore == 50)
        check("opts.dismissImmediate", bridge.dismissal(from: dict) == .immediate)
        check("opts.dismissSeconds", bridge.dismissal(from: ["dismiss": 60.0]) != .immediate)
        check("opts.dismissDefault", bridge.dismissal(from: [:]) == .default)
        check("opts.alert", bridge.alert(from: dict) != nil)
        check("opts.noAlert", bridge.alert(from: [:]) == nil)

        // An opts object with no presentation keys must yield "" so end() knows to keep the
        // current content rather than blanking the activity with an empty tree.
        check("json.emptyIsEmpty", bridge.layoutJSON(from: ctx.evaluateScript("({ key: 'k' })")!).isEmpty)

        check("size.underLimitPasses", bridge.oversizeMessage(json, api: "start") == nil)
        check("size.overLimitFails", bridge.oversizeMessage(
            String(repeating: "x", count: LoomActivityAttributes.maxLayoutBytes + 1), api: "start") != nil)

        if failures.isEmpty {
            print("[ActivityBridge] self-check passed")
        } else {
            print("[ActivityBridge] self-check FAILED: \(failures.joined(separator: ", "))")
        }
        return failures.isEmpty
    }
    #endif

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
