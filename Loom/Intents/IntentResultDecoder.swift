import Foundation

// __loom_result__ is always JSON.stringify(...)'d text by the time it reaches Swift (see
// ModuleBundler.executionFooter) — a JS string result arrives quoted ("\"hello\"").
// Best-effort unwraps to a natural, unquoted primitive for Shortcuts/Siri; objects, arrays,
// null, and decode failures fall back to the raw JSON text as-is. No attempt at full typed
// fidelity (ReturnsValue<Int> vs <Bool>) — impossible to vary per project at compile time
// anyway, and not required by M5's done-criteria wording ("passes... back," not "typed").
enum IntentResultDecoder {
    nonisolated static func unwrap(_ jsonText: String?) -> String? {
        guard let jsonText, let data = jsonText.data(using: .utf8) else { return jsonText }
        guard let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return jsonText
        }
        switch value {
        case let b as Bool: return b ? "true" : "false"
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        default: return jsonText  // object, array, or null — pass through as JSON text
        }
    }
}
