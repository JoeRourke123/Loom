import Foundation
import JavaScriptCore

// Implements Loom.log and wires console.log → Loom.log.debug.
final class LogBridge {
    private let ctx: JSContext
    private let project: LoomProject
    private let session: RunSession
    private let runLoop: CFRunLoop

    nonisolated init(ctx: JSContext, project: LoomProject, session: RunSession, runLoop: CFRunLoop) {
        self.ctx = ctx
        self.project = project
        self.session = session
        self.runLoop = runLoop
    }

    nonisolated func makeObject() -> JSValue {
        let obj = JSValue(newObjectIn: ctx)!
        for level in LogLevel.allCases {
            let l = level
            let block: @convention(block) (JSValue, JSValue) -> Void = { [weak self] msgVal, dataVal in
                self?.log(level: l, msgVal: msgVal, dataVal: dataVal)
            }
            obj.setObject(block, forKeyedSubscript: l.rawValue as NSString)
        }
        return obj
    }

    // Replaces the global console with one that routes to Loom.log.
    nonisolated func wireConsole() {
        let console = JSValue(newObjectIn: ctx)!
        let debugBlock: @convention(block) (JSValue) -> Void = { [weak self] v in self?.log(level: .debug, msgVal: v, dataVal: JSValue(undefinedIn: v.context)) }
        let infoBlock:  @convention(block) (JSValue) -> Void = { [weak self] v in self?.log(level: .info,  msgVal: v, dataVal: JSValue(undefinedIn: v.context)) }
        let warnBlock:  @convention(block) (JSValue) -> Void = { [weak self] v in self?.log(level: .warn,  msgVal: v, dataVal: JSValue(undefinedIn: v.context)) }
        let errorBlock: @convention(block) (JSValue) -> Void = { [weak self] v in self?.log(level: .error, msgVal: v, dataVal: JSValue(undefinedIn: v.context)) }
        console.setObject(debugBlock, forKeyedSubscript: "log"   as NSString)
        console.setObject(infoBlock,  forKeyedSubscript: "info"  as NSString)
        console.setObject(warnBlock,  forKeyedSubscript: "warn"  as NSString)
        console.setObject(errorBlock, forKeyedSubscript: "error" as NSString)
        ctx.setObject(console, forKeyedSubscript: "console" as NSString)
    }

    private func log(level: LogLevel, msgVal: JSValue?, dataVal: JSValue?) {
        let message: String
        if let mv = msgVal, !mv.isUndefined, !mv.isNull {
            if mv.isObject, let obj = mv.toObject(),
               JSONSerialization.isValidJSONObject(obj),
               let data = try? JSONSerialization.data(withJSONObject: obj),
               let str = String(data: data, encoding: .utf8) {
                message = str
            } else {
                message = mv.toString() ?? ""
            }
        } else {
            message = ""
        }

        var dataStr: String? = nil
        if let dv = dataVal, !dv.isUndefined, !dv.isNull, dv.isObject,
           let obj = dv.toObject(),
           JSONSerialization.isValidJSONObject(obj),
           let data = try? JSONSerialization.data(withJSONObject: obj),
           let str = String(data: data, encoding: .utf8) {
            dataStr = str
        }

        let entry = LogEntry(
            runId: session.runId,
            projectName: project.name,
            level: level,
            message: message,
            data: dataStr
        )
        session.append(entry)
        LogStore.shared.append(entry)
    }
}
