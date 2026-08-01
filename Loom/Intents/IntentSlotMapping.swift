import Foundation

// Maps a project's declared intent.inputs (author-defined, unknown at compile time) onto
// RunScriptWithInputIntent's fixed set of generically-typed slots (App Intent parameters are
// compile-time constants — there's no way to synthesize new AppIntent parameter types per
// project at runtime). Deterministic: same input always produces the same assignment, so both
// perform()'s ctx.input construction and the Group 9 lint warning ("N string parameters
// declared, only 4 supported") agree on what got dropped.
struct SlotAssignment {
    let param: LoomConfig.IntentParam
    let slotIndex: Int  // 0-based within its type's slot group
}

enum IntentSlotMapping {
    nonisolated static let stringSlots = 4
    nonisolated static let numberSlots = 2
    nonisolated static let booleanSlots = 2
    nonisolated static let dateSlots = 1

    nonisolated static func assign(_ params: [LoomConfig.IntentParam]) -> [SlotAssignment] {
        var counts: [LoomConfig.IntentParam.ParamType: Int] = [:]
        var result: [SlotAssignment] = []
        for param in params {
            let used = counts[param.type, default: 0]
            guard used < limit(for: param.type) else { continue }  // over the bound — dropped
            result.append(SlotAssignment(param: param, slotIndex: used))
            counts[param.type] = used + 1
        }
        return result
    }

    nonisolated static func limit(for type: LoomConfig.IntentParam.ParamType) -> Int {
        switch type {
        case .string: return stringSlots
        case .number: return numberSlots
        case .boolean: return booleanSlots
        case .date: return dateSlots
        }
    }

    // MARK: - Self-check

    #if DEBUG
    @discardableResult
    nonisolated static func runSelfCheck() -> Bool {
        var failures: [String] = []
        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            if !condition() { failures.append(name) }
        }
        func param(_ name: String, _ type: LoomConfig.IntentParam.ParamType) -> LoomConfig.IntentParam {
            LoomConfig.IntentParam(name: name, type: type, description: nil, optional: false)
        }

        // Basic — declaration order preserved per type, mixed types interleaved.
        let basic = assign([param("city", .string), param("count", .number), param("unit", .string)])
        check("basic.count", basic.count == 3)
        check("basic.city.slot0", basic.first { $0.param.name == "city" }?.slotIndex == 0)
        check("basic.unit.slot1", basic.first { $0.param.name == "unit" }?.slotIndex == 1)
        check("basic.count.slot0", basic.first { $0.param.name == "count" }?.slotIndex == 0)

        // Over the string bound (4) — 5th string param is dropped, not mis-slotted.
        let overflow = assign([
            param("a", .string), param("b", .string), param("c", .string),
            param("d", .string), param("e", .string),
        ])
        check("overflow.count", overflow.count == 4)
        check("overflow.dropsE", !overflow.contains { $0.param.name == "e" })
        check("overflow.keepsD", overflow.contains { $0.param.name == "d" && $0.slotIndex == 3 })

        if failures.isEmpty {
            print("[IntentSlotMapping] self-check passed")
        } else {
            print("[IntentSlotMapping] self-check FAILED: \(failures.joined(separator: ", "))")
        }
        return failures.isEmpty
    }
    #endif
}
