import Foundation
import JavaScriptCore
import UIKit

// Implements Loom.clipboard — synchronous UIPasteboard access.
final class ClipboardBridge {
    private let ctx: JSContext

    nonisolated init(ctx: JSContext) {
        self.ctx = ctx
    }

    nonisolated func makeObject() -> JSValue {
        let obj = JSValue(newObjectIn: ctx)!

        let capturedCtx = ctx
        let readBlock: @convention(block) () -> JSValue = { [weak self] in
            guard let self else { return JSValue(undefinedIn: capturedCtx) }
            var text: String = ""
            DispatchQueue.main.sync { text = UIPasteboard.general.string ?? "" }
            return JSValue(object: text, in: self.ctx) ?? JSValue(undefinedIn: self.ctx)
        }

        let writeBlock: @convention(block) (JSValue) -> Void = { textVal in
            let text = textVal.toString() ?? ""
            DispatchQueue.main.sync { UIPasteboard.general.string = text }
        }

        obj.setObject(readBlock,  forKeyedSubscript: "read"  as NSString)
        obj.setObject(writeBlock, forKeyedSubscript: "write" as NSString)
        return obj
    }
}
