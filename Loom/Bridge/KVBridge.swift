import Foundation
import JavaScriptCore

// Implements Loom.kv — synchronous iCloud key-value bridge.
final class KVBridge {
    private let ctx: JSContext
    private let store: KVStore

    nonisolated init(ctx: JSContext, project: LoomProject) {
        self.ctx = ctx
        self.store = KVStore(projectName: project.name)
    }

    nonisolated func makeObject() -> JSValue {
        let obj = JSValue(newObjectIn: ctx)!

        let getBlock: @convention(block) (JSValue) -> JSValue = { [weak self] keyVal in
            guard let self else { return JSValue(undefinedIn: keyVal.context) }
            let key = keyVal.toString() ?? ""
            if let val = self.store.get(key) {
                return JSValue(object: val as AnyObject, in: self.ctx) ?? JSValue(undefinedIn: self.ctx)
            }
            return JSValue(undefinedIn: self.ctx)
        }

        let setBlock: @convention(block) (JSValue, JSValue) -> Void = { [weak self] keyVal, valVal in
            guard let self else { return }
            let key = keyVal.toString() ?? ""
            if let obj = valVal.toObject() {
                self.store.set(key, value: obj)
            }
        }

        let deleteBlock: @convention(block) (JSValue) -> Void = { [weak self] keyVal in
            self?.store.delete(keyVal.toString() ?? "")
        }

        let capturedCtx = ctx
        let listBlock: @convention(block) () -> JSValue = { [weak self] in
            guard let self else { return JSValue(undefinedIn: capturedCtx) }
            let keys = self.store.listKeys()
            return JSValue(object: keys as NSArray, in: self.ctx) ?? JSValue(undefinedIn: self.ctx)
        }

        obj.setObject(getBlock,    forKeyedSubscript: "get"    as NSString)
        obj.setObject(setBlock,    forKeyedSubscript: "set"    as NSString)
        obj.setObject(deleteBlock, forKeyedSubscript: "delete" as NSString)
        obj.setObject(listBlock,   forKeyedSubscript: "list"   as NSString)
        return obj
    }
}
