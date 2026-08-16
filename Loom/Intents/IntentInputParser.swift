import Foundation

// Turns the Shortcuts "Input" parameter into the dictionary a script receives as ctx.input.
// Shortcuts hands a Dictionary variable over as its JSON text representation, so the parameter
// is declared as text and parsed here; `Get Dictionary from Input` is the documented inverse.
//
// Replaces IntentSlotMapping's fixed 4-string/2-number/2-boolean/1-date slots. Those existed
// because @Parameter is a compile-time constant while a project's intent.inputs schema isn't
// known until runtime — the cost was a hard cap on parameter count plus generic "Text 1"
// labels in the Shortcuts editor that no amount of Zod metadata could rename. One JSON
// parameter has neither limit, and round-trips Shortcuts' own Dictionary type.
//
// intent.inputs survives as a *schema* rather than a slot allocator: a Shortcuts text field
// hands over "12" where the script expects 12, so declared params are coerced to their declared
// type and required ones are enforced. Undeclared keys pass through untouched — intent.inputs
// is optional, and a script that declares nothing should still receive whatever it was sent,
// nested objects and arrays included.
enum IntentInputParser {
    /// Empty input is legitimate: the parameter is optional so the action can be dropped into a
    /// shortcut before its dictionary is wired up, and a script may declare no inputs at all.
    static func parse(_ raw: String?, schema: [LoomConfig.IntentParam]) throws -> [String: Any] {
        var values = try decode(raw)

        for param in schema {
            let value = values[param.name]
            if value == nil || value is NSNull {
                guard param.optional else {
                    throw LoomIntentError.badInput(
                        "Missing required input \"\(param.name)\" (\(param.type.rawValue))."
                    )
                }
                // An explicit null would reach the script as `null`, which reads very differently
                // from "not supplied" on the JS side. Absent is absent.
                values.removeValue(forKey: param.name)
                continue
            }
            values[param.name] = try coerce(value!, to: param.type, name: param.name)
        }

        return values
    }

    private static func decode(_ raw: String?) throws -> [String: Any] {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [:] }

        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else {
            throw LoomIntentError.badInput(
                "Input isn't valid JSON. Pass a Dictionary, or text holding a JSON object."
            )
        }
        guard let dictionary = object as? [String: Any] else {
            throw LoomIntentError.badInput("Input must be a dictionary, not \(typeName(of: object)).")
        }
        return dictionary
    }

    // MARK: - Coercion

    private static func coerce(
        _ value: Any,
        to type: LoomConfig.IntentParam.ParamType,
        name: String
    ) throws -> Any {
        switch type {
        case .string:
            if let string = value as? String { return string }
            if let number = value as? NSNumber { return text(for: number) }
            throw mismatch(name, type, value)

        case .number:
            if let number = value as? NSNumber, !isBoolean(number) { return number.doubleValue }
            if let string = value as? String,
               let parsed = Double(string.trimmingCharacters(in: .whitespaces)) { return parsed }
            throw mismatch(name, type, value)

        case .boolean:
            if let number = value as? NSNumber, isBoolean(number) { return number.boolValue }
            if let number = value as? NSNumber { return number.doubleValue != 0 }
            if let string = value as? String, let parsed = boolean(from: string) { return parsed }
            throw mismatch(name, type, value)

        case .date:
            // Scripts have always received dates as ISO 8601 strings — the slot path formatted
            // them that way before handing them over — so normalise rather than pass an epoch
            // number or whatever loose format arrived.
            if let string = value as? String, let date = isoDate(from: string) { return iso.string(from: date) }
            if let number = value as? NSNumber, !isBoolean(number) {
                return iso.string(from: Date(timeIntervalSince1970: number.doubleValue))
            }
            throw mismatch(name, type, value)
        }
    }

    private static func mismatch(
        _ name: String,
        _ type: LoomConfig.IntentParam.ParamType,
        _ value: Any
    ) -> LoomIntentError {
        var message = "Input \"\(name)\" should be a \(type.rawValue), got \(typeName(of: value))."
        if type == .date {
            // Worth spelling out: a Shortcuts Date variable stringifies to a localised, unparseable
            // form ("10 August 2026 at 14:32"), and the fix isn't guessable from a type mismatch.
            message += " Run it through Format Date with the ISO 8601 format first."
        }
        return .badInput(message)
    }

    // JSONSerialization boxes both numbers and booleans as NSNumber; CFBoolean is the only way
    // to tell `true` from `1`, which matters in both directions here.
    private static func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private static func text(for number: NSNumber) -> String {
        if isBoolean(number) { return number.boolValue ? "true" : "false" }
        if number.doubleValue == number.doubleValue.rounded(),
           abs(number.doubleValue) < 1e15 {
            return String(number.int64Value)
        }
        return String(number.doubleValue)
    }

    private static func boolean(from string: String) -> Bool? {
        switch string.trimmingCharacters(in: .whitespaces).lowercased() {
        case "true", "yes", "1": return true
        case "false", "no", "0": return false
        default: return nil
        }
    }

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func isoDate(from string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        return iso.date(from: trimmed) ?? isoFractional.date(from: trimmed)
    }

    private static func typeName(of value: Any) -> String {
        switch value {
        case let number as NSNumber: return isBoolean(number) ? "a boolean" : "a number"
        case is String: return "text"
        case is [Any]: return "a list"
        case is [String: Any]: return "a dictionary"
        case is NSNull: return "null"
        default: return "an unsupported value"
        }
    }

    // MARK: - Self-check

    #if DEBUG
    @discardableResult
    static func runSelfCheck() -> Bool {
        var failures: [String] = []
        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            if !condition() { failures.append(name) }
        }
        func param(
            _ name: String,
            _ type: LoomConfig.IntentParam.ParamType,
            optional: Bool = false
        ) -> LoomConfig.IntentParam {
            LoomConfig.IntentParam(name: name, type: type, description: nil, optional: optional)
        }
        func parsed(_ raw: String?, _ schema: [LoomConfig.IntentParam] = []) -> [String: Any]? {
            try? parse(raw, schema: schema)
        }
        func rejects(_ raw: String?, _ schema: [LoomConfig.IntentParam] = []) -> Bool {
            (try? parse(raw, schema: schema)) == nil
        }

        // No input at all is valid — the parameter is optional.
        check("empty.nil", parsed(nil)?.isEmpty == true)
        check("empty.blank", parsed("   ")?.isEmpty == true)

        // Undeclared keys pass through with their JSON types intact, nesting included.
        let passthrough = parsed(#"{"a":1,"b":"x","c":true,"d":{"e":[1,2]}}"#)
        check("passthrough.count", passthrough?.count == 4)
        check("passthrough.number", (passthrough?["a"] as? NSNumber)?.doubleValue == 1)
        check("passthrough.nested", ((passthrough?["d"] as? [String: Any])?["e"] as? [Any])?.count == 2)

        // Coercion of declared params — the reason the schema still exists. A Shortcuts text
        // field hands over "12", and the script expects 12.
        let coerced = parsed(
            #"{"amount":"12.5","note":7,"done":"yes","when":"2026-08-10T14:32:00Z"}"#,
            [param("amount", .number), param("note", .string), param("done", .boolean), param("when", .date)]
        )
        check("coerce.number", coerced?["amount"] as? Double == 12.5)
        check("coerce.string", coerced?["note"] as? String == "7")
        check("coerce.boolean", coerced?["done"] as? Bool == true)
        check("coerce.date", (coerced?["when"] as? String)?.hasPrefix("2026-08-10T14:32:00") == true)

        // 1 must stay a number and true must stay a boolean — both are NSNumber after decoding.
        let boxed = parsed(#"{"n":1,"b":true}"#, [param("n", .string), param("b", .string)])
        check("boxed.numberText", boxed?["n"] as? String == "1")
        check("boxed.boolText", boxed?["b"] as? String == "true")

        // Required vs optional.
        check("required.missing", rejects("{}", [param("city", .string)]))
        check("optional.missing", parsed("{}", [param("city", .string, optional: true)])?.isEmpty == true)
        check("optional.explicitNull", parsed(#"{"city":null}"#, [param("city", .string, optional: true)])?.isEmpty == true)
        check("required.explicitNull", rejects(#"{"city":null}"#, [param("city", .string)]))

        // Malformed and wrong-shaped input are rejected, not silently swallowed.
        check("reject.notJSON", rejects("not json"))
        check("reject.array", rejects("[1,2,3]"))
        check("reject.scalar", rejects("42"))
        check("reject.badNumber", rejects(#"{"n":"abc"}"#, [param("n", .number)]))
        check("reject.badDate", rejects(#"{"d":"10 August 2026 at 14:32"}"#, [param("d", .date)]))
        check("reject.listForString", rejects(#"{"s":[1]}"#, [param("s", .string)]))

        if failures.isEmpty {
            print("[IntentInputParser] self-check passed")
        } else {
            print("[IntentInputParser] self-check FAILED: \(failures.joined(separator: ", "))")
        }
        return failures.isEmpty
    }
    #endif
}
