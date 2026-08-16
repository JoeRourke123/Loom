import Foundation
import GRDB

/// A Splunk-flavoured query over the log store.
///
/// ```
/// level>=warn project=Weather "connection timeout" -retry last=24h | stats count by project
/// ```
///
/// Bare words match the message. `field=value` filters, comma-separated values mean "any of",
/// `!=` negates, and `level` also takes `>=` / `<=` because its four values are ordered. `last=`
/// takes a relative window. A single `| stats count [by field]` or `| head N` may follow.
///
/// Unlike `TableQuery` there is no identifier whitelist to enforce: every column name here comes
/// from the `Field` enum below and is a compile-time constant, so only values are ever bound.
nonisolated struct LogQuery: Hashable {
    var filters: [Filter] = []
    var text: [TextMatch] = []
    /// Relative window in seconds, resolved against `now` at build time rather than stored as a
    /// Date — that keeps the parsed query pure, comparable and reproducible in the self-check.
    var lastSeconds: Int?
    var stats: Stats?
    var limit = defaultLimit

    static let defaultLimit = 200
    static let maxLimit = 5_000

    struct Filter: Hashable {
        var field: Field
        var op: Op
        var values: [String]
    }

    struct TextMatch: Hashable {
        var text: String
        var negated = false
    }

    struct Stats: Hashable {
        /// nil is a grand total — `| stats count` with no `by`.
        var by: Field?
    }

    enum Field: String, CaseIterable {
        case level, project, message, data, run

        /// The physical column. Constant per case — never interpolated from user input.
        var column: String {
            switch self {
            case .level:   return "level"
            case .project: return "projectName"
            case .message: return "message"
            case .data:    return "data"
            case .run:     return "runId"
            }
        }

        /// Text fields match by substring; the rest match exactly.
        var isText: Bool { self == .message || self == .data }
        /// Only `data` is nullable, which changes what a negated filter has to mean.
        var isNullable: Bool { self == .data }
    }

    enum Op: String, CaseIterable {
        case eq = "=", ne = "!=", ge = ">=", le = "<=", gt = ">", lt = "<"

        var isComparison: Bool { self != .eq && self != .ne }
        /// Longest first, so `!=` and `>=` win over `=` when scanning a token.
        static let byLength = allCases.sorted { $0.rawValue.count > $1.rawValue.count }
    }

    enum QueryError: LocalizedError {
        case unknownField(String)
        case unknownLevel(String)
        case comparisonNotSupported(Field)
        case badDuration(String)
        case unknownCommand(String)
        case badStats(String)
        case badHead(String)
        case unterminatedQuote

        var errorDescription: String? {
            switch self {
            case .unknownField(let name):
                return "Unknown field “\(name)”. Try: \(Field.allCases.map(\.rawValue).joined(separator: ", "))."
            case .unknownLevel(let value):
                return "Unknown level “\(value)”. Try: \(LogLevel.allCases.map(\.rawValue).joined(separator: ", "))."
            case .comparisonNotSupported(let field):
                return "“\(field.rawValue)” can't be compared with > or <. Only level can — its values are ordered."
            case .badDuration(let value):
                return "Can't read the time window “\(value)”. Try last=30m, last=24h or last=7d."
            case .unknownCommand(let name):
                return "Unknown command “\(name)”. Try: stats, head."
            case .badStats(let detail):
                return "stats: \(detail). Try “| stats count” or “| stats count by level”."
            case .badHead(let value):
                return "head needs a row count, got “\(value)”."
            case .unterminatedQuote:
                return "Unclosed quote."
            }
        }
    }
}

// MARK: - Parsing

nonisolated extension LogQuery {
    static func parse(_ input: String) throws -> LogQuery {
        var query = LogQuery()
        let segments = try tokenize(input)
        guard let search = segments.first else { return query }

        for token in search {
            if token.quoted {
                query.text.append(TextMatch(text: token.text))
            } else if try consumeFieldExpression(token.text, into: &query) {
                continue
            } else if token.text.hasPrefix("-"), token.text.count > 1 {
                query.text.append(TextMatch(text: String(token.text.dropFirst()), negated: true))
            } else if !token.text.isEmpty {
                query.text.append(TextMatch(text: token.text))
            }
        }

        for command in segments.dropFirst() {
            try query.apply(command: command)
        }
        return query
    }

    /// Consumes `field<op>value`, and the `last=` window which is written the same way but sets a
    /// time bound rather than a filter.
    ///
    /// Returns whether the token was consumed, rather than an optional Filter: nil would have to
    /// mean both "not a field expression, treat it as text" and "handled, but it produced no
    /// filter", and conflating those made `last=24h` set the window *and* get searched for as a
    /// literal message substring.
    private static func consumeFieldExpression(_ token: String, into query: inout LogQuery) throws -> Bool {
        guard let op = Op.byLength.first(where: { token.contains($0.rawValue) }),
              let range = token.range(of: op.rawValue)
        else { return false }

        let name = String(token[..<range.lowerBound]).lowercased()
        let rawValue = String(token[range.upperBound...])
        guard !name.isEmpty, !rawValue.isEmpty else { return false }

        if name == "last" {
            guard op == .eq else { throw QueryError.badDuration(rawValue) }
            query.lastSeconds = try duration(rawValue)
            return true
        }

        guard let field = Field(rawValue: name) else { throw QueryError.unknownField(name) }
        let values = rawValue.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !values.isEmpty else { return false }

        if op.isComparison, field != .level { throw QueryError.comparisonNotSupported(field) }
        if field == .level {
            for value in values where LogLevel(rawValue: value.lowercased()) == nil {
                throw QueryError.unknownLevel(value)
            }
        }
        query.filters.append(Filter(field: field, op: op, values: values))
        return true
    }

    private mutating func apply(command tokens: [Token]) throws {
        guard let head = tokens.first?.text.lowercased() else { return }
        switch head {
        case "stats":
            let rest = tokens.dropFirst().map { $0.text.lowercased() }
            guard rest.first == "count" else { throw QueryError.badStats("only `count` is supported") }
            let after = Array(rest.dropFirst())
            if after.isEmpty {
                stats = Stats(by: nil)
            } else if after.count == 2, after[0] == "by" {
                guard let field = Field(rawValue: after[1]) else { throw QueryError.unknownField(after[1]) }
                stats = Stats(by: field)
            } else {
                throw QueryError.badStats("expected `by <field>`")
            }
        case "head":
            guard let value = tokens.dropFirst().first?.text, let n = Int(value), n > 0 else {
                throw QueryError.badHead(tokens.dropFirst().first?.text ?? "")
            }
            limit = min(n, Self.maxLimit)
        default:
            throw QueryError.unknownCommand(head)
        }
    }

    private static func duration(_ value: String) throws -> Int {
        guard let unit = value.last, let amount = Int(value.dropLast()), amount > 0 else {
            throw QueryError.badDuration(value)
        }
        switch unit {
        case "s": return amount
        case "m": return amount * 60
        case "h": return amount * 3_600
        case "d": return amount * 86_400
        case "w": return amount * 604_800
        default:  throw QueryError.badDuration(value)
        }
    }

    struct Token: Hashable {
        var text: String
        var quoted = false
    }

    /// Splits into `|`-separated segments of tokens, honouring double quotes. A quoted token keeps
    /// its quoted-ness so `"level=error"` stays a phrase to search for rather than a filter.
    static func tokenize(_ input: String) throws -> [[Token]] {
        var segments: [[Token]] = [[]]
        var current = ""
        var quoted = false
        var inQuotes = false

        func flush() {
            if !current.isEmpty || quoted {
                segments[segments.count - 1].append(Token(text: current, quoted: quoted))
            }
            current = ""
            quoted = false
        }

        for char in input {
            if char == "\"" {
                inQuotes.toggle()
                if !inQuotes { quoted = true }
                continue
            }
            if inQuotes {
                current.append(char)
                continue
            }
            switch char {
            case "|": flush(); segments.append([])
            case " ", "\t", "\n": flush()
            default: current.append(char)
            }
        }
        if inQuotes { throw QueryError.unterminatedQuote }
        flush()
        // Only trailing empties are dropped. Filtering empties out wholesale would remove segment 0
        // for a query that opens with a pipe — promoting `| stats count by level` into the
        // search-terms slot, where it silently became four words to grep the message for.
        while segments.count > 1, segments[segments.count - 1].isEmpty { segments.removeLast() }
        return segments
    }
}

// MARK: - SQL

nonisolated extension LogQuery {
    /// `now` is a parameter rather than `Date()` so the query stays a pure function of its input —
    /// the self-check needs a fixed clock.
    func build(now: Date) -> (sql: String, args: [DatabaseValue]) {
        var clauses: [String] = []
        var args: [DatabaseValue] = []

        for filter in filters {
            let column = "\"\(filter.field.column)\""
            if filter.field.isText {
                // Substring match, with `*` as the user-facing wildcard. Escaping runs first so a
                // literal % or _ in a message can't act as one.
                let patterns = filter.values.map { "%\(Self.escapeLike($0))%".replacingOccurrences(of: "*", with: "%") }
                let likes = patterns.map { _ in "\(column) LIKE ? ESCAPE '\\'" }
                args += patterns.map { $0.databaseValue }
                if filter.op == .ne {
                    // `data` is nullable, and `NOT LIKE` on NULL is NULL — without the IS NULL arm,
                    // "data doesn't mention X" would silently drop every log with no data at all.
                    let negated = "NOT (\(likes.joined(separator: " OR ")))"
                    clauses.append(filter.field.isNullable ? "(\(column) IS NULL OR \(negated))" : negated)
                } else {
                    clauses.append("(\(likes.joined(separator: " OR ")))")
                }
            } else {
                let values = filter.field == .level
                    ? Self.levels(for: filter)
                    : filter.values
                guard !values.isEmpty else { clauses.append("0"); continue }
                let placeholders = Array(repeating: "?", count: values.count).joined(separator: ", ")
                clauses.append("\(column) \(filter.op == .ne ? "NOT IN" : "IN") (\(placeholders))")
                args += values.map { $0.databaseValue }
            }
        }

        for match in text {
            let pattern = "%\(Self.escapeLike(match.text).replacingOccurrences(of: "*", with: "%"))%"
            clauses.append("\"message\" \(match.negated ? "NOT LIKE" : "LIKE") ? ESCAPE '\\'")
            args.append(pattern.databaseValue)
        }

        if let lastSeconds {
            clauses.append("\"timestamp\" >= ?")
            args.append(now.addingTimeInterval(-Double(lastSeconds)).databaseValue)
        }

        let with = clauses.isEmpty ? "" : " WHERE " + clauses.joined(separator: " AND ")
        let capped = min(max(limit, 1), Self.maxLimit)

        guard let stats else {
            return ("SELECT * FROM \"logs\"\(with) ORDER BY \"timestamp\" DESC LIMIT \(capped)", args)
        }
        guard let by = stats.by else {
            return ("SELECT '' AS \"key\", COUNT(*) AS \"count\" FROM \"logs\"\(with)", args)
        }
        let column = "\"\(by.column)\""
        return (
            "SELECT \(column) AS \"key\", COUNT(*) AS \"count\" FROM \"logs\"\(with) "
            + "GROUP BY \(column) ORDER BY \"count\" DESC LIMIT \(capped)",
            args
        )
    }

    /// Expands a level filter into the concrete set it covers, so an ordered comparison becomes an
    /// indexed `IN` over a text column rather than a lexical comparison — `'warn' >= 'error'` is
    /// true alphabetically, which is the opposite of what the user asked for.
    private static func levels(for filter: Filter) -> [String] {
        let wanted = filter.values.compactMap { LogLevel(rawValue: $0.lowercased()) }
        guard filter.op.isComparison, let pivot = wanted.first else {
            return wanted.map(\.rawValue)
        }
        return LogLevel.allCases.filter { level in
            switch filter.op {
            case .ge: return level.severity >= pivot.severity
            case .gt: return level.severity > pivot.severity
            case .le: return level.severity <= pivot.severity
            case .lt: return level.severity < pivot.severity
            default:  return false
            }
        }.map(\.rawValue)
    }

    /// `%` and `_` are LIKE wildcards; the user-facing wildcard is `*`, converted after escaping.
    private static func escapeLike(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}

nonisolated extension LogLevel {
    /// `allCases` is declared in severity order — debug, info, warn, error.
    var severity: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

// MARK: - Summary

nonisolated extension LogQuery {
    var isEmpty: Bool {
        filters.isEmpty && text.isEmpty && lastSeconds == nil && stats == nil
    }

    /// One line describing what ran, for the results header and Siri's spoken reply.
    var summary: String {
        var parts: [String] = []
        for filter in filters {
            parts.append("\(filter.field.rawValue)\(filter.op.rawValue)\(filter.values.joined(separator: ","))")
        }
        parts += text.map { "\($0.negated ? "-" : "")“\($0.text)”" }
        if let lastSeconds { parts.append("last \(Self.humanDuration(lastSeconds))") }
        if let stats {
            parts.append(stats.by.map { "count by \($0.rawValue)" } ?? "count")
        }
        return parts.isEmpty ? "all logs" : parts.joined(separator: " · ")
    }

    static func humanDuration(_ seconds: Int) -> String {
        switch seconds {
        case ..<60:      return "\(seconds)s"
        case ..<3_600:   return "\(seconds / 60)m"
        case ..<86_400:  return "\(seconds / 3_600)h"
        default:         return "\(seconds / 86_400)d"
        }
    }
}

// MARK: - Self-check

#if DEBUG
nonisolated extension LogQuery {
    static func runSelfCheck() {
        let clock = Date(timeIntervalSince1970: 1_800_000_000)

        // A whole query parses into the right shape.
        let full = try! parse(#"level>=warn project=Weather "connection timeout" -retry last=24h | head 50"#)
        assert(full.filters.count == 2, "\(full.filters)")
        assert(full.text == [TextMatch(text: "connection timeout"),
                             TextMatch(text: "retry", negated: true)], "\(full.text)")
        assert(full.lastSeconds == 86_400)
        assert(full.limit == 50)
        // `last=` must set the window and nothing else — it is written like a filter but isn't one,
        // and a token consumed for one purpose must not also be searched for as literal text.
        assert(try! parse("last=1h").text.isEmpty, "\(try! parse("last=1h").text)")

        // Placeholder count must match arg count, or GRDB throws at execute with a useless message.
        let built = full.build(now: clock)
        assert(built.sql.filter { $0 == "?" }.count == built.args.count, built.sql)

        // level>=warn becomes an IN over the levels at or above it. A literal `level >= 'warn'`
        // would compare text, where 'error' < 'warn' — the exact opposite of the intent.
        // Compared as DatabaseValues, not via `description` — that's `String(reflecting:)`, which
        // quotes and escapes, so asserting on it tests GRDB's debug formatting rather than the value.
        let warn = try! parse("level>=warn").build(now: clock)
        assert(warn.sql.contains(#""level" IN (?, ?)"#), warn.sql)
        assert(warn.args == ["warn".databaseValue, "error".databaseValue], "\(warn.args)")
        let below = try! parse("level<info").build(now: clock)
        assert(below.args == ["debug".databaseValue], "expected only debug, got \(below.args)")

        // Comma values are "any of"; != negates the same set.
        let list = try! parse("level=warn,error")
        assert(list.filters.first?.values == ["warn", "error"])
        assert(try! parse("project!=Weather").build(now: clock).sql.contains("NOT IN"))

        // Quoted text is a phrase, not a filter — otherwise you could never search for the literal
        // string "level=error" appearing in a message.
        let quoted = try! parse(#""level=error""#)
        assert(quoted.filters.isEmpty && quoted.text == [TextMatch(text: "level=error")], "\(quoted)")

        // LIKE metacharacters in user input stay literal; `*` is the wildcard that doesn't.
        let pct = try! parse("50%").build(now: clock)
        assert(pct.args == [#"%50\%%"#.databaseValue], "\(pct.args)")
        let star = try! parse("time*out").build(now: clock)
        assert(star.args == ["%time%out%".databaseValue], "\(star.args)")

        // A negated filter on the nullable column must not drop rows that have no data at all.
        let noData = try! parse("data!=secret").build(now: clock)
        assert(noData.sql.contains(#""data" IS NULL OR"#), noData.sql)
        // …while the non-nullable one needs no such arm.
        assert(!(try! parse("message!=x").build(now: clock).sql.contains("IS NULL")))

        // stats swaps the projection and groups; without `by` it's a single total.
        let byLevel = try! parse("| stats count by level").build(now: clock)
        assert(byLevel.sql.hasPrefix(#"SELECT "level" AS "key", COUNT(*) AS "count""#), byLevel.sql)
        assert(byLevel.sql.contains(#"GROUP BY "level""#), byLevel.sql)
        let total = try! parse("| stats count").build(now: clock)
        assert(total.sql.contains("COUNT(*)") && !total.sql.contains("GROUP BY"), total.sql)
        // A leading pipe means the search segment is empty, not absent — the command must not slide
        // into its place and be read as search terms.
        assert(try! parse("| stats count by level").text.isEmpty, "\(try! parse("| stats count by level").text)")
        // …and a query with both parts still splits at the right place.
        let both = try! parse("level=error | stats count by project")
        assert(both.filters.count == 1 && both.text.isEmpty && both.stats?.by == .project, "\(both)")

        // Time windows resolve against the passed clock, not the wall clock.
        let windowed = try! parse("last=2h").build(now: clock)
        assert(windowed.args.count == 1 && windowed.sql.contains(#""timestamp" >= ?"#), windowed.sql)

        // Bad input reports what to do rather than silently matching nothing.
        for bad in ["nosuchfield=1", "level=nosuchlevel", "project>=x", "last=24x", "| nope", "| stats sum", "| head zero", #""unclosed"#] {
            assert((try? parse(bad)) == nil, "expected a parse error for: \(bad)")
        }

        // An empty query is "everything", not "nothing".
        let blank = try! parse("   ")
        assert(blank.isEmpty)
        assert(!blank.build(now: clock).sql.contains("WHERE"), blank.build(now: clock).sql)

        // head is clamped, so a pasted `| head 999999999` can't pull the table into memory.
        assert(try! parse("| head 999999999").limit == maxLimit)
    }
}
#endif
