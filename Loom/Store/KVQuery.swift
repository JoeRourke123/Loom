import Foundation

/// A filter over one project's KV entries.
///
/// The counterpart to `TableQuery` for the Database tab's KV section, but deliberately not the same
/// type: KV is a flat string→string map with no schema and no SQL, so there is nothing to whitelist,
/// no identifiers to quote, and only two fields to filter or sort on. It applies in memory —
/// `NSUbiquitousKeyValueStore` hands over the whole dictionary at once, and a project's key count is
/// bounded by iCloud's own 1024-key limit, so there is nothing to push down to a query engine.
///
/// Not `Codable`, unlike `TableQuery`: KV filters are not saveable and not reachable from an App
/// Intent (see ADR-018 — the intents query tables). Add persistence when something needs to replay
/// one, not before.
nonisolated struct KVQuery: Hashable {
    var project: String
    var keyOp: Op = .contains
    var keyFilter = ""
    var valueFilter = ""
    var sortBy: Field = .key
    var descending = false

    enum Op: String, CaseIterable {
        case contains, startsWith, equals

        var label: String {
            switch self {
            case .contains:   return "contains"
            case .startsWith: return "starts with"
            case .equals:     return "is"
            }
        }
    }

    enum Field: String, CaseIterable {
        case key, value

        var label: String { rawValue.capitalized }
    }

    /// Filters and sorts in one pass. Case-insensitive throughout — KV keys are hand-written by
    /// script authors and a case-sensitive filter reads as a broken search box.
    func apply(to entries: [KVEntry]) -> [KVEntry] {
        let key = keyFilter.trimmingCharacters(in: .whitespaces)
        let value = valueFilter.trimmingCharacters(in: .whitespaces)

        let matched = entries.filter { entry in
            if !key.isEmpty {
                switch keyOp {
                case .contains:   guard entry.key.localizedCaseInsensitiveContains(key) else { return false }
                case .startsWith: guard entry.key.lowercased().hasPrefix(key.lowercased()) else { return false }
                case .equals:     guard entry.key.caseInsensitiveCompare(key) == .orderedSame else { return false }
                }
            }
            if !value.isEmpty, !entry.value.localizedCaseInsensitiveContains(value) { return false }
            return true
        }

        return matched.sorted { lhs, rhs in
            let a = sortBy == .key ? lhs.key : lhs.value
            let b = sortBy == .key ? rhs.key : rhs.value
            // localizedStandardCompare so "item2" sorts before "item10", which is what a
            // script writing numbered keys would expect.
            let order = a.localizedStandardCompare(b)
            return descending ? order == .orderedDescending : order == .orderedAscending
        }
    }

    /// One line for the collapsed accessory strip and the results header.
    func summary(matching: Int) -> String {
        var parts = [project]
        let key = keyFilter.trimmingCharacters(in: .whitespaces)
        if !key.isEmpty { parts.append("\(keyOp.label) “\(key)”") }
        let value = valueFilter.trimmingCharacters(in: .whitespaces)
        if !value.isEmpty { parts.append("value “\(value)”") }
        if sortBy != .key || descending {
            parts.append("by \(sortBy.label.lowercased())\(descending ? " ↓" : " ↑")")
        }
        parts.append("\(matching) key\(matching == 1 ? "" : "s")")
        return parts.joined(separator: " · ")
    }
}

#if DEBUG
nonisolated extension KVQuery {
    static func runSelfCheck() {
        let entries = [
            KVEntry(key: "cache.weather", value: "{\"temp\":14}"),
            KVEntry(key: "cache.rates", value: "{\"GBP\":1}"),
            KVEntry(key: "sync.cursor", value: "4821"),
            KVEntry(key: "item10", value: "b"),
            KVEntry(key: "item2", value: "a"),
        ]
        var query = KVQuery(project: "Demo")

        // No filters is the identity, not an empty result.
        assert(query.apply(to: entries).count == entries.count)

        // Prefix is the case the "sync." / "cache." naming convention actually calls for.
        query.keyOp = .startsWith
        query.keyFilter = "cache."
        assert(query.apply(to: entries).map(\.key) == ["cache.rates", "cache.weather"])

        // Case-insensitive, or the filter reads as broken against hand-written keys.
        query.keyFilter = "CACHE."
        assert(query.apply(to: entries).count == 2)

        // Key and value filters are AND'ed.
        query.valueFilter = "GBP"
        assert(query.apply(to: entries).map(\.key) == ["cache.rates"])

        // Numeric-aware sort: item2 before item10, which a plain < gets backwards.
        var numeric = KVQuery(project: "Demo")
        numeric.keyOp = .startsWith
        numeric.keyFilter = "item"
        assert(numeric.apply(to: entries).map(\.key) == ["item2", "item10"])
        numeric.descending = true
        assert(numeric.apply(to: entries).map(\.key) == ["item10", "item2"])

        // Sorting by value uses the value, not the key.
        var byValue = KVQuery(project: "Demo")
        byValue.keyOp = .startsWith
        byValue.keyFilter = "item"
        byValue.sortBy = .value
        assert(byValue.apply(to: entries).map(\.value) == ["a", "b"])

        // `equals` is exact, not a prefix.
        var exact = KVQuery(project: "Demo")
        exact.keyOp = .equals
        exact.keyFilter = "cache"
        assert(exact.apply(to: entries).isEmpty)

        // JSON round-trips through the editor without being rewritten into a multi-line blob.
        let compact = "{\"a\":1,\"b\":[2,3]}"
        let pretty = KVStore.prettyJSON(compact)
        assert(pretty?.contains("\n") == true, "expected pretty-printed JSON")
        assert(KVStore.compactJSON(pretty ?? "") == compact, "round-trip changed the value")
        assert(KVStore.prettyJSON("not json") == nil)
        assert(KVStore.prettyJSON("08:30") == nil, "a plain string must not be treated as JSON")

        // A stored `false` must not read as "0" — NSUbiquitousKeyValueStore has no boolean type.
        assert(KVStore.display(NSNumber(value: false)) == "false")
        assert(KVStore.display(NSNumber(value: 0)) == "0")
        assert(KVStore.display(NSNumber(value: true)) == "true")
    }
}
#endif
