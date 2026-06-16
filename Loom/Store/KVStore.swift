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
    static func allEntries(for projectName: String) -> [(key: String, value: String)] {
        let store = NSUbiquitousKeyValueStore.default
        let prefix = "\(projectName):"
        return store.dictionaryRepresentation
            .filter { $0.key.hasPrefix(prefix) }
            .map { (key: String($0.key.dropFirst(prefix.count)), value: "\($0.value)") }
            .sorted { $0.key < $1.key }
    }
}

// Helper: run on main, return value. Safe to call from any thread.
@discardableResult
private func onMain<T>(_ work: @escaping () -> T) -> T {
    if Thread.isMainThread { return work() }
    var result: T!
    DispatchQueue.main.sync { result = work() }
    return result
}
