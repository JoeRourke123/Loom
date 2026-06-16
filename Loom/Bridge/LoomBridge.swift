import Foundation
import JavaScriptCore

// Injects the `Loom` global into a JSContext and owns all bridge namespaces.
// Created and used exclusively on the dedicated script thread (nonisolated context).
final class LoomBridge {
    let ctx: JSContext
    let project: LoomProject
    let session: RunSession
    let runLoop: CFRunLoop

    private let log: LogBridge
    private let network: NetworkBridge
    private let files: FilesBridge
    private let db: DatabaseBridge
    private let kv: KVBridge
    private let ui: UIBridge
    private let notify: NotifyBridge
    private let device: DeviceBridge
    private let clipboard: ClipboardBridge
    private let location: LocationBridge
    private let speech: SpeechBridge
    private let contacts: ContactsBridge
    private let calendar: CalendarBridge
    private let photos: PhotosBridge
    private let camera: CameraBridge
    private let health: HealthBridge
    private let ai: AIBridge

    nonisolated init(ctx: JSContext, project: LoomProject, session: RunSession, runLoop: CFRunLoop) {
        self.ctx = ctx
        self.project = project
        self.session = session
        self.runLoop = runLoop
        log       = LogBridge(ctx: ctx, project: project, session: session, runLoop: runLoop)
        network   = NetworkBridge(ctx: ctx, project: project, runLoop: runLoop)
        files     = FilesBridge(ctx: ctx, project: project, runLoop: runLoop)
        db        = DatabaseBridge(ctx: ctx, project: project, runLoop: runLoop)
        kv        = KVBridge(ctx: ctx, project: project)
        ui        = UIBridge(ctx: ctx, project: project, runLoop: runLoop)
        notify    = NotifyBridge(ctx: ctx, project: project, runLoop: runLoop)
        device    = DeviceBridge(ctx: ctx)
        clipboard = ClipboardBridge(ctx: ctx)
        location  = LocationBridge(ctx: ctx)
        speech    = SpeechBridge(ctx: ctx)
        contacts  = ContactsBridge(ctx: ctx)
        calendar  = CalendarBridge(ctx: ctx)
        photos    = PhotosBridge(ctx: ctx, project: project)
        camera    = CameraBridge(ctx: ctx, project: project)
        health    = HealthBridge(ctx: ctx)
        ai        = AIBridge(ctx: ctx)
    }

    // Sets up the Loom global and wires console to LogBridge.
    nonisolated func inject() {
        ctx.evaluateScript("(function(){})") // warm JSC
        // Pre-cache Promise helpers so makePromise can call them via JSValue.call()
        // rather than ctx.evaluateScript() — calling a cached function is re-entrant-safe
        // from within a JSC microtask drain; evaluateScript is not.
        ctx.evaluateScript("""
        var __loomResolve = function(v){ return Promise.resolve(v); };
        var __loomReject  = function(m){ return Promise.reject(new Error(m)); };
        """)

        let loom = JSValue(newObjectIn: ctx)!
        loom.setObject(log.makeObject(),       forKeyedSubscript: "log"       as NSString)
        loom.setObject(network.makeObject(),   forKeyedSubscript: "network"   as NSString)
        loom.setObject(files.makeObject(),     forKeyedSubscript: "files"     as NSString)
        loom.setObject(db.makeObject(),        forKeyedSubscript: "db"        as NSString)
        loom.setObject(kv.makeObject(),        forKeyedSubscript: "kv"        as NSString)
        loom.setObject(ui.makeObject(),        forKeyedSubscript: "ui"        as NSString)
        loom.setObject(notify.makeObject(),    forKeyedSubscript: "notify"    as NSString)
        loom.setObject(device.makeObject(),    forKeyedSubscript: "device"    as NSString)
        loom.setObject(clipboard.makeObject(), forKeyedSubscript: "clipboard" as NSString)
        loom.setObject(location.makeObject(),  forKeyedSubscript: "location"  as NSString)
        loom.setObject(speech.makeObject(),    forKeyedSubscript: "speech"    as NSString)
        loom.setObject(contacts.makeObject(),  forKeyedSubscript: "contacts"  as NSString)
        loom.setObject(calendar.makeObject(),  forKeyedSubscript: "calendar"  as NSString)
        loom.setObject(photos.makeObject(),    forKeyedSubscript: "photos"    as NSString)
        loom.setObject(camera.makeObject(),    forKeyedSubscript: "camera"    as NSString)
        loom.setObject(health.makeObject(),    forKeyedSubscript: "health"    as NSString)
        loom.setObject(ai.makeObject(),        forKeyedSubscript: "ai"        as NSString)
        ctx.setObject(loom, forKeyedSubscript: "Loom" as NSString)

        log.wireConsole()
    }

    // Blocks the script thread until the executor calls resolve or reject,
    // then returns a pre-settled Promise so JSC drains it as a microtask.
    nonisolated func makePromise(
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
