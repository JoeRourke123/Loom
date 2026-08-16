import Foundation

// Per-project iCloud key-value store. Keys namespaced as "<project>:<key>".
// NSUbiquitousKeyValueStore is documented as main-thread-only; all methods
// here dispatch to main synchronously so callers need not care.
struct KVStore {
    private let namespace: String
    private let store = NSUbiquitousKeyValueStore.default

    init(projectName: String) {
        self.namespace = projectName
    }

    private func key(_ k: String) -> String { "\(namespace):\(k)" }

    func get(_ k: String) -> Any? {
        onMain { self.store.object(forKey: self.key(k)) }
    }

    func set(_ k: String, value: Any) {
        onMain {
            if JSONSerialization.isValidJSONObject(value),
               let data = try? JSONSerialization.data(withJSONObject: value),
               let str = String(data: data, encoding: .utf8) {
                self.store.set(str, forKey: self.key(k))
            } else {
                self.store.set(value, forKey: self.key(k))
            }
            self.store.synchronize()
        }
    }

    func delete(_ k: String) {
        onMain {
            self.store.removeObject(forKey: self.key(k))
            self.store.synchronize()
        }
    }

    func listKeys() -> [String] {
        let prefix = "\(namespace):"
        let keys: [String] = onMain {
            self.store.dictionaryRepresentation.keys
                .filter { $0.hasPrefix(prefix) }
                .map { String($0.dropFirst(prefix.count)) }
                .sorted()
        }
        return keys
    }

    // Returns all (shortKey, value) pairs for a project, for the KV viewer.
    static func allEntries(for projectName: String) -> [KVEntry] {
        let store = NSUbiquitousKeyValueStore.default
        let prefix = "\(projectName):"
        return store.dictionaryRepresentation
            .filter { $0.key.hasPrefix(prefix) }
            .map { KVEntry(key: String($0.key.dropFirst(prefix.count)), value: display($0.value)) }
            .sorted { $0.key < $1.key }
    }

    /// How a stored value reads in the viewer.
    ///
    /// `"\(value)"` isn't enough: NSUbiquitousKeyValueStore has no boolean storage class, so a JS
    /// `false` comes back as an NSNumber and prints as "0" — indistinguishable from a real zero
    /// unless the CFBoolean type is checked for explicitly.
    static func display(_ value: Any) -> String {
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue ? "true" : "false"
        }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return "\(value)"
    }

    /// Re-formatted JSON if the value is a JSON object or array, else nil.
    ///
    /// `set` JSON-serialises objects to a compact string before storing, so anything a script wrote
    /// as an object arrives here as one unreadable line.
    static func prettyJSON(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("["),
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                  withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: pretty, encoding: .utf8)
        else { return nil }
        return string
    }

    /// Collapses pretty-printed JSON back to the compact form `set` stores, so a round-trip through
    /// the editor doesn't rewrite a value the script wrote as one line into a multi-line blob.
    static func compactJSON(_ value: String) -> String? {
        guard let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let compact = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: compact, encoding: .utf8)
        else { return nil }
        return string
    }
}

nonisolated struct KVEntry: Identifiable, Hashable {
    var key: String
    var value: String
    var id: String { key }
}

// Helper: run on main, return value. Safe to call from any thread.
@discardableResult
private func onMain<T>(_ work: @escaping () -> T) -> T {
    if Thread.isMainThread { return work() }
    var result: T!
    DispatchQueue.main.sync { result = work() }
    return result
}
