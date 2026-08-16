import Foundation

/// A structured query over one ScriptDB table.
///
/// Codable so it can be saved and replayed by an App Intent; Hashable so a SwiftUI `.task(id:)`
/// re-runs the moment any option changes.
///
/// NB: adding a non-Optional stored property to this type (or to any of its nested types) would
/// make SavedQueryStore's decode fail with keyNotFound on every previously-saved blob and silently
/// wipe the user's whole query list — Swift's synthesized Codable ignores property defaults for
/// missing keys. New fields must be Optional. Same trap as AIProvider.
nonisolated struct TableQuery: Codable, Hashable {
    /// Fully namespaced: "<project>__<table>" or "shared__<table>".
    var table: String
    var filters: [Filter] = []
    /// AND across the filters when true, OR when false. One flat group, no nesting — `inList`
    /// covers the case nesting would otherwise be needed for.
    var matchAll = true
    /// Free text, LIKE'd across every column and OR'd, then AND'ed with the filter group.
    var search = ""
    var sorts: [Sort] = []
    var aggregate: Aggregate?
    var limit = 100
    /// Display-only — never reaches SQL. Queries always `SELECT *`, so a saved query keeps working
    /// when a script adds a column, and the renderer decides what's worth the screen width.
    var visibleColumns: [String]?

    struct Filter: Codable, Hashable, Identifiable {
        var id = UUID()
        var column: String
        var op: Op = .eq
        var value = ""
    }

    struct Sort: Codable, Hashable, Identifiable {
        var id = UUID()
        var column: String
        var descending = false
    }

    struct Aggregate: Codable, Hashable {
        var function: Function = .count
        /// nil for COUNT(*); required for every other function.
        var column: String?
        var groupBy: String?
    }

    enum Op: String, Codable, CaseIterable {
        case eq, ne, gt, gte, lt, lte
        case contains, startsWith, endsWith
        case inList
        case isNull, isNotNull

        var label: String {
            switch self {
            case .eq:         return "is"
            case .ne:         return "is not"
            case .gt:         return "greater than"
            case .gte:        return "at least"
            case .lt:         return "less than"
            case .lte:        return "at most"
            case .contains:   return "contains"
            case .startsWith: return "starts with"
            case .endsWith:   return "ends with"
            case .inList:     return "is one of"
            case .isNull:     return "has no value"
            case .isNotNull:  return "has any value"
            }
        }

        var takesValue: Bool { self != .isNull && self != .isNotNull }

        /// Only the six plain comparisons are emitted this way; the rest are built structurally in
        /// `build(columns:)` and never read this. Enumerated rather than `default:`-ed so adding an
        /// operator fails to compile until it's been thought about here too.
        var sql: String {
            switch self {
            // IS / IS NOT rather than = / <>: null-safe, and identical for non-NULL operands.
            // `col <> 'x'` silently drops every row where col is NULL, which reads as a missing row.
            case .eq:  return "IS"
            case .ne:  return "IS NOT"
            case .gt:  return ">"
            case .gte: return ">="
            case .lt:  return "<"
            case .lte: return "<="
            case .contains, .startsWith, .endsWith, .inList, .isNull, .isNotNull: return ""
            }
        }
    }

    enum Function: String, Codable, CaseIterable {
        case count, sum, avg, min, max

        var label: String {
            switch self {
            case .count: return "Count"
            case .sum:   return "Sum"
            case .avg:   return "Average"
            case .min:   return "Minimum"
            case .max:   return "Maximum"
            }
        }

        var sql: String { rawValue.uppercased() }
        var needsColumn: Bool { self != .count }
    }

    enum QueryError: LocalizedError {
        case unknownColumn(String)
        case unknownTable(String)
        case missingAggregateColumn(Function)

        var errorDescription: String? {
            switch self {
            case .unknownColumn(let name):
                return "This query refers to a column named \"\(name)\", which no longer exists in the table."
            case .unknownTable(let name):
                return "No table named \"\(name)\" exists."
            case .missingAggregateColumn(let fn):
                return "\(fn.label) needs a column to summarise."
            }
        }
    }
}

// MARK: - SQL generation

nonisolated extension TableQuery {
    /// The alias every aggregate result is returned under, so the sort whitelist and the results
    /// renderer have one agreed name for it.
    static let aggregateAlias = "value"

    /// Upper bound on `limit`, so a saved query can't ask for the whole table into memory.
    static let maxLimit = 10_000

    /// Builds parameterised SQL for this query.
    ///
    /// Trust boundary: saved queries persist and are replayed by App Intents, so every identifier is
    /// matched against `columns` before it reaches the string — a whitelist, not escaping. Values
    /// are always bound and always as text: SQLite applies NUMERIC affinity to an untyped operand
    /// compared against a numeric column, so `amount > ?` with "5" compares numerically on an
    /// INTEGER column and lexically on a TEXT one, which is what you want in both cases.
    ///
    /// `columns` must be the live schema (`ScriptDB.columns(of:)`), not the keys of a result row —
    /// `rowToDict` drops NULLs, so a column that is null in every row would be missing.
    func build(columns: [String]) throws -> (sql: String, args: [String]) {
        let known = Set(columns)
        func quoted(_ name: String) throws -> String {
            guard known.contains(name) else { throw QueryError.unknownColumn(name) }
            return name.sqlQuoted
        }

        var args: [String] = []
        var groups: [String] = []

        if !filters.isEmpty {
            var clauses: [String] = []
            for filter in filters {
                let col = try quoted(filter.column)
                switch filter.op {
                case .isNull:
                    clauses.append("\(col) IS NULL")
                case .isNotNull:
                    clauses.append("\(col) IS NOT NULL")
                case .inList:
                    let items = filter.value.split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    // `IN ()` is a SQLite syntax error, so an empty list becomes a literal false.
                    guard !items.isEmpty else { clauses.append("0"); break }
                    clauses.append("\(col) IN (\(Array(repeating: "?", count: items.count).joined(separator: ", ")))")
                    args += items
                case .contains, .startsWith, .endsWith:
                    clauses.append("\(col) LIKE ? ESCAPE '\\'")
                    let term = Self.escapeLike(filter.value)
                    switch filter.op {
                    case .startsWith: args.append("\(term)%")
                    case .endsWith:   args.append("%\(term)")
                    default:          args.append("%\(term)%")
                    }
                case .eq, .ne, .gt, .gte, .lt, .lte:
                    clauses.append("\(col) \(filter.op.sql) ?")
                    args.append(filter.value)
                }
            }
            groups.append("(" + clauses.joined(separator: matchAll ? " AND " : " OR ") + ")")
        }

        let term = search.trimmingCharacters(in: .whitespaces)
        if !term.isEmpty, !columns.isEmpty {
            // Its own parenthesised group, AND'ed with the filters. Without the parens, "Match Any"
            // would OR the search terms in among the filters and silently widen to everything.
            groups.append("(" + columns
                .map { "\($0.sqlQuoted) LIKE ? ESCAPE '\\'" }
                .joined(separator: " OR ") + ")")
            args += Array(repeating: "%\(Self.escapeLike(term))%", count: columns.count)
        }

        let whereSQL = groups.isEmpty ? "" : " WHERE " + groups.joined(separator: " AND ")
        let from = " FROM \(table.sqlQuoted)"

        var sql: String
        let sortable: Set<String>

        if let aggregate {
            var selects: [String] = []
            if let group = aggregate.groupBy { selects.append(try quoted(group)) }
            let target: String
            if aggregate.function.needsColumn {
                guard let column = aggregate.column else {
                    throw QueryError.missingAggregateColumn(aggregate.function)
                }
                target = try quoted(column)
            } else {
                target = "*"
            }
            selects.append("\(aggregate.function.sql)(\(target)) AS \(Self.aggregateAlias.sqlQuoted)")
            sql = "SELECT " + selects.joined(separator: ", ") + from + whereSQL
            if let group = aggregate.groupBy { sql += " GROUP BY \(try quoted(group))" }
            // An aggregate result's columns are the group column and the alias — not the table's.
            sortable = Set([aggregate.groupBy, Self.aggregateAlias].compactMap { $0 })
        } else {
            sql = "SELECT *" + from + whereSQL
            sortable = known
        }

        // A grouped count is only ever read biggest-first.
        let ordering = (aggregate != nil && sorts.isEmpty)
            ? [Sort(column: Self.aggregateAlias, descending: true)]
            : sorts
        let orderClauses: [String] = try ordering.map { sort in
            guard sortable.contains(sort.column) else { throw QueryError.unknownColumn(sort.column) }
            return "\(sort.column.sqlQuoted)\(sort.descending ? " DESC" : " ASC")"
        }
        if !orderClauses.isEmpty { sql += " ORDER BY " + orderClauses.joined(separator: ", ") }

        // Interpolated, not bound: it's an Int clamped to a sane range, so there's nothing to
        // inject, and it keeps `args` homogeneous — which is what makes the self-check readable.
        sql += " LIMIT \(min(max(limit, 1), Self.maxLimit))"
        return (sql, args)
    }

    /// `%` and `_` are LIKE wildcards, so a user searching for "50%" must not also match "5012".
    /// Backslash first, or the escapes we add would themselves get escaped.
    private static func escapeLike(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}

// MARK: - Repair

nonisolated extension TableQuery {
    /// Drops every clause referring to a column that no longer exists, and returns their names.
    ///
    /// `build(columns:)` throws on an unknown identifier, which is right for a trust boundary but
    /// wrong as the user's experience: a saved query whose table was recreated without one column
    /// would show an error instead of results, with no way to fix it from the results screen. This
    /// degrades it to a runnable query plus a note about what was ignored.
    mutating func pruneUnknownColumns(against columns: [String]) -> [String] {
        let known = Set(columns)
        var dropped: [String] = []
        func note(_ name: String) {
            if !dropped.contains(name) { dropped.append(name) }
        }

        for filter in filters where !known.contains(filter.column) { note(filter.column) }
        filters = filters.filter { known.contains($0.column) }

        visibleColumns = visibleColumns?.filter { known.contains($0) }

        if var updated = aggregate {
            if let column = updated.column, !known.contains(column) {
                note(column)
                updated.column = nil
            }
            if let group = updated.groupBy, !known.contains(group) {
                note(group)
                updated.groupBy = nil
            }
            // A summarise with no column left to summarise isn't a query — drop it wholesale.
            aggregate = (updated.function.needsColumn && updated.column == nil) ? nil : updated
        }

        // Sort keys are validated against the *result* columns, which for an aggregate are the
        // group column and the alias — so this has to run after the aggregate above is settled.
        let sortable: Set<String>
        if let aggregate {
            sortable = Set([aggregate.groupBy, Self.aggregateAlias].compactMap { $0 })
        } else {
            sortable = known
        }
        for sort in sorts where !sortable.contains(sort.column) { note(sort.column) }
        sorts = sorts.filter { sortable.contains($0.column) }

        return dropped
    }
}

// MARK: - Summary

nonisolated extension TableQuery {
    /// Human-readable table name — strips the "<project>__" / "shared__" namespace prefix.
    static func friendlyName(_ table: String) -> String {
        guard let range = table.range(of: "__") else { return table }
        return String(table[range.upperBound...])
    }

    /// Owning project name, or nil for a shared table.
    static func projectName(_ table: String) -> String? {
        guard let range = table.range(of: "__") else { return nil }
        let name = String(table[..<range.lowerBound])
        return name == "shared" ? nil : name
    }

    /// One line describing what this query does, for the collapsed accessory strip and the results
    /// header. Deliberately not the SQL — the SQL preview lives in the sheet.
    var summary: String {
        var parts = [Self.friendlyName(table)]
        if let aggregate {
            let target = aggregate.function.needsColumn ? (aggregate.column ?? "?") : "all"
            var text = "\(aggregate.function.label) of \(target)"
            if let group = aggregate.groupBy { text += " by \(group)" }
            parts.append(text)
        }
        if !filters.isEmpty {
            parts.append("\(filters.count) filter\(filters.count == 1 ? "" : "s")")
        }
        if !search.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append("“\(search)”")
        }
        if let sort = sorts.first {
            parts.append("by \(sort.column)\(sort.descending ? " ↓" : " ↑")")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Self-check

#if DEBUG
nonisolated extension TableQuery {
    /// The one check worth having in this feature: everything downstream is glue, but a query that
    /// generates wrong SQL is silently wrong — it returns rows, just not the right ones.
    static func runSelfCheck() {
        let cols = ["id", "amount", "note", "category"]
        func sql(_ build: (inout TableQuery) -> Void) -> (sql: String, args: [String]) {
            var query = TableQuery(table: "Budget__expenses")
            build(&query)
            return try! query.build(columns: cols)
        }

        // Placeholder count must match arg count, across every operator at once. An arity mismatch
        // throws at execute time with a message that points nowhere near the cause.
        let everything = sql {
            $0.filters = [
                .init(column: "amount", op: .gt, value: "5"),
                .init(column: "amount", op: .lte, value: "500"),
                .init(column: "note", op: .eq, value: "x"),
                .init(column: "note", op: .ne, value: "y"),
                .init(column: "note", op: .contains, value: "a"),
                .init(column: "note", op: .startsWith, value: "b"),
                .init(column: "note", op: .endsWith, value: "c"),
                .init(column: "category", op: .inList, value: "food, rent ,, travel"),
                .init(column: "category", op: .isNull, value: ""),
                .init(column: "id", op: .isNotNull, value: ""),
            ]
            $0.search = "coffee"
            $0.sorts = [.init(column: "amount", descending: true)]
        }
        assert(everything.sql.filter { $0 == "?" }.count == everything.args.count,
               "placeholder/arg arity mismatch: \(everything.sql) — \(everything.args)")
        // 7 single-value filters + 3 from the inList (the empty item is dropped) + 4 search columns.
        // isNull/isNotNull contribute none.
        assert(everything.args.count == 14, "unexpected arg count \(everything.args.count)")

        // Unknown identifiers are rejected, not quoted-and-hoped — this is what protects a saved
        // query replayed by an App Intent after a script recreated the table without the column.
        var stale = TableQuery(table: "Budget__expenses")
        stale.filters = [.init(column: "dropped_column", op: .eq, value: "1")]
        assert((try? stale.build(columns: cols)) == nil, "unknown filter column must throw")
        var staleSort = TableQuery(table: "Budget__expenses")
        staleSort.sorts = [.init(column: "dropped_column")]
        assert((try? staleSort.build(columns: cols)) == nil, "unknown sort column must throw")

        // `IN ()` is a syntax error; an empty list has to become valid SQL that matches nothing.
        let empty = sql { $0.filters = [.init(column: "category", op: .inList, value: " , ,")] }
        assert(empty.sql.contains("(0)") && empty.args.isEmpty, "empty inList: \(empty.sql)")

        // LIKE metacharacters in user input must be literal.
        let pct = sql { $0.filters = [.init(column: "note", op: .contains, value: "50%_x")] }
        assert(pct.args == ["%50\\%\\_x%"], "LIKE escaping: \(pct.args)")
        assert(pct.sql.contains("ESCAPE '\\'"), "missing ESCAPE clause: \(pct.sql)")

        // Null-safe equality. `<>` would silently exclude NULL rows.
        let ne = sql { $0.filters = [.init(column: "note", op: .ne, value: "x")] }
        assert(ne.sql.contains("\"note\" IS NOT ?"), "expected IS NOT: \(ne.sql)")

        // Match Any must not let the search term OR its way in among the filters.
        let anyMatch = sql {
            $0.matchAll = false
            $0.filters = [.init(column: "amount", op: .gt, value: "5"),
                          .init(column: "amount", op: .lt, value: "1")]
            $0.search = "z"
        }
        assert(anyMatch.sql.contains("OR \"amount\" < ?) AND ("), "search group not isolated: \(anyMatch.sql)")

        // Aggregates select the group column plus the alias, and sort by the alias by default.
        let grouped = sql { $0.aggregate = .init(function: .count, column: nil, groupBy: "category") }
        assert(grouped.sql.hasPrefix("SELECT \"category\", COUNT(*) AS \"value\""), grouped.sql)
        assert(grouped.sql.contains("GROUP BY \"category\" ORDER BY \"value\" DESC"), grouped.sql)
        // …and reject table columns as sort keys, since they aren't in the result.
        var badAggSort = TableQuery(table: "Budget__expenses")
        badAggSort.aggregate = .init(function: .count, column: nil, groupBy: "category")
        badAggSort.sorts = [.init(column: "note")]
        assert((try? badAggSort.build(columns: cols)) == nil, "non-grouped sort column must throw")
        var noAggCol = TableQuery(table: "Budget__expenses")
        noAggCol.aggregate = .init(function: .sum, column: nil, groupBy: nil)
        assert((try? noAggCol.build(columns: cols)) == nil, "SUM without a column must throw")

        // Limit is clamped, never bound, never user-controlled beyond the range.
        let huge = sql { $0.limit = 99_999_999 }
        assert(huge.sql.hasSuffix("LIMIT \(maxLimit)"), huge.sql)
        let zero = sql { $0.limit = 0 }
        assert(zero.sql.hasSuffix("LIMIT 1"), zero.sql)

        // Identifiers are quoted with embedded quotes doubled, so a table or column carrying one —
        // both come from script-controlled names via sqlite_master — can't break out of the string.
        // GRDB's own quotedDatabaseIdentifier does NOT do this; see `String.sqlQuoted`.
        var odd = TableQuery(table: "Weird\"Name__t")
        odd.filters = [.init(column: "we\"ird", op: .eq, value: "1")]
        let oddSQL = try! odd.build(columns: ["we\"ird"]).sql
        assert(oddSQL.contains("\"Weird\"\"Name__t\""), oddSQL)
        assert(oddSQL.contains("\"we\"\"ird\""), oddSQL)
    }
}
#endif
