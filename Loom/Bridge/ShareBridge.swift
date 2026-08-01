import Foundation
import JavaScriptCore

// Implements Loom.share.input() — for a share-triggered run, ctx.input is already
// { type, value } (see DeepLinkHandler.handleShare), so this is a thin synchronous re-export,
// not real bridge logic. Kept as a real class purely for consistency with the other 17
// namespaces.
final class ShareBridge {
    private let ctx: JSContext

    nonisolated init(ctx: JSContext) {
        self.ctx = ctx
    }

    nonisolated func makeObject() -> JSValue {
        let obj = JSValue(newObjectIn: ctx)!

        let capturedCtx = ctx
        let inputBlock: @convention(block) () -> JSValue = {
            capturedCtx.evaluateScript("ctx.input") ?? JSValue(undefinedIn: capturedCtx)
        }

        obj.setObject(inputBlock, forKeyedSubscript: "input" as NSString)
        return obj
    }
}
