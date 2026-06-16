import Foundation
import JavaScriptCore

// Implements Loom.db — auto-migrating SQLite ORM.
// Table names are prefixed: "<project>__<table>" for private, "shared__<table>" for shared.
final class DatabaseBridge {
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

        let tableBlock: @convention(block) (JSValue) -> JSValue = { [weak self] nameVal in
            guard let self else { return JSValue(undefinedIn: nameVal.context) }
            let name = nameVal.toString() ?? ""
            let fullName = "\(self.project.name)__\(name)"
            return self.makeTableProxy(table: fullName, shared: false)
        }

        let sharedObj = JSValue(newObjectIn: ctx)!
        let sharedTableBlock: @convention(block) (JSValue) -> JSValue = { [weak self] nameVal in
            guard let self else { return JSValue(undefinedIn: nameVal.context) }
            let name = nameVal.toString() ?? ""
            return self.makeTableProxy(table: "shared__\(name)", shared: true)
        }
        sharedObj.setObject(sharedTableBlock, forKeyedSubscript: "table" as NSString)

        obj.setObject(tableBlock, forKeyedSubscript: "table"  as NSString)
        obj.setObject(sharedObj,  forKeyedSubscript: "shared" as NSString)
        return obj
    }

    nonisolated private func makeTableProxy(table: String, shared: Bool) -> JSValue {
        let proxy = JSValue(newObjectIn: ctx)!

        let insertBlock: @convention(block) (JSValue) -> JSValue = { [weak self] rowVal in
            guard let self else { return JSValue(undefinedIn: rowVal.context) }
            let row = rowVal.toDictionary() as? [String: Any] ?? [:]
            return self.makePromise { resolve, reject in
                Task.detached {
                    do { try await ScriptDB.shared.insert(into: table, row: row, shared: shared); resolve(nil) }
                    catch { reject(error.localizedDescription) }
                }
            }
        }

        let selectBlock: @convention(block) (JSValue) -> JSValue = { [weak self] whereVal in
            guard let self else { return JSValue(undefinedIn: whereVal.context) }
            let conditions = whereVal.isObject ? whereVal.toDictionary() as? [String: Any] : nil
            return self.makePromise { resolve, reject in
                Task.detached {
                    do { let rows = try await ScriptDB.shared.select(from: table, where: conditions, shared: shared); resolve(rows as NSArray) }
                    catch { reject(error.localizedDescription) }
                }
            }
        }

        let updateBlock: @convention(block) (JSValue, JSValue) -> JSValue = { [weak self] whereVal, valuesVal in
            guard let self else { return JSValue(undefinedIn: whereVal.context) }
            let conditions = whereVal.toDictionary() as? [String: Any] ?? [:]
            let values = valuesVal.toDictionary() as? [String: Any] ?? [:]
            return self.makePromise { resolve, reject in
                Task.detached {
                    do { let n = try await ScriptDB.shared.update(in: table, where: conditions, set: values, shared: shared); resolve(n) }
                    catch { reject(error.localizedDescription) }
                }
            }
        }

        let deleteBlock: @convention(block) (JSValue) -> JSValue = { [weak self] whereVal in
            guard let self else { return JSValue(undefinedIn: whereVal.context) }
            let conditions = whereVal.toDictionary() as? [String: Any] ?? [:]
            return self.makePromise { resolve, reject in
                Task.detached {
                    do { let n = try await ScriptDB.shared.delete(from: table, where: conditions, shared: shared); resolve(n) }
                    catch { reject(error.localizedDescription) }
                }
            }
        }

        proxy.setObject(insertBlock, forKeyedSubscript: "insert" as NSString)
        proxy.setObject(selectBlock, forKeyedSubscript: "select" as NSString)
        proxy.setObject(updateBlock, forKeyedSubscript: "update" as NSString)
        proxy.setObject(deleteBlock, forKeyedSubscript: "delete" as NSString)
        return proxy
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
