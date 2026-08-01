import SwiftUI
import Foundation

// Shows how a project's loom() config appears to Siri/Shortcuts, plus lint warnings for
// vague/missing descriptions and other easy-to-miss config mistakes. Reads
// ConfigExtractor.extract synchronously — a brace scan + evaluating a sub-1KB literal is
// fast enough not to need a loading state, matching the Console panel's snappy toggle feel.
struct SiriPreviewView: View {
    let project: LoomProject
    @State private var config: LoomConfig?
    @State private var findings: [LintFinding] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let config {
                    phraseSection(config)
                    if let inputs = config.intent?.inputs, !inputs.isEmpty {
                        inputsSection(inputs)
                    }
                    if let entities = config.entities, !entities.isEmpty {
                        entitiesSection(entities)
                    }
                    if !findings.isEmpty {
                        lintSection
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: project.folderURL) { load() }
    }

    private func load() {
        guard let source = try? String(contentsOf: project.mainFileURL, encoding: .utf8) else {
            config = LoomConfig(name: project.name, description: "")
            findings = []
            return
        }
        let extracted = ConfigExtractor.extract(source: source, fallbackName: project.name)
        config = extracted
        findings = SiriLint.check(config: extracted, rawSource: source)
    }

    // MARK: - Sections

    private func phraseSection(_ config: LoomConfig) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Run \(config.name) in Loom", systemImage: "waveform")
                .font(.callout.weight(.medium))
            Text(config.description.isEmpty ? "No description" : config.description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func inputsSection(_ inputs: [LoomConfig.IntentParam]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Siri will ask for")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(inputs, id: \.name) { param in
                HStack(alignment: .top, spacing: 6) {
                    Text(param.name)
                        .font(.caption.weight(.medium))
                    Text("(\(param.type.rawValue)\(param.optional ? ", optional" : ""))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text(param.description ?? "no description")
                        .font(.caption)
                        .foregroundStyle(param.description == nil ? .orange : .secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func entitiesSection(_ entities: [String: LoomConfig.EntityType]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Entities indexed to Spotlight")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(entities.keys.sorted(), id: \.self) { typeName in
                if let spec = entities[typeName] {
                    Text("\(spec.displayName) — via \(spec.provider)()")
                        .font(.caption)
                }
            }
        }
    }

    private var lintSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Lint", systemImage: "exclamationmark.triangle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            ForEach(findings) { finding in
                Text("• \(finding.message)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct LintFinding: Identifiable {
    let id = UUID()
    let message: String
}

enum SiriLint {
    // Every check here is a hint, not a hard error — a project with no intent.inputs or
    // entities at all should produce zero findings, not warnings about sections it never
    // declared.
    static func check(config: LoomConfig, rawSource: String) -> [LintFinding] {
        var findings: [LintFinding] = []

        let description = config.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if description.isEmpty {
            findings.append(LintFinding(message: "No description — Siri has nothing to go on for this script."))
        } else if config.description == "A new Loom script." {
            findings.append(LintFinding(message: "Description is still the scaffolded placeholder."))
        }

        if let inputs = config.intent?.inputs {
            for param in inputs where (param.description ?? "").isEmpty {
                findings.append(LintFinding(message: "\"\(param.name)\" has no description — weaker Siri natural-language matching."))
            }

            var counts: [LoomConfig.IntentParam.ParamType: Int] = [:]
            for param in inputs { counts[param.type, default: 0] += 1 }
            for type in counts.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
                let count = counts[type] ?? 0
                let limit = IntentSlotMapping.limit(for: type)
                if count > limit {
                    findings.append(LintFinding(
                        message: "\(count) \(type.rawValue) parameters declared, only \(limit) supported; extras ignored."
                    ))
                }
            }
        }

        if let entities = config.entities {
            for typeName in entities.keys.sorted() {
                guard let spec = entities[typeName] else { continue }
                if !hasExport(named: spec.provider, in: rawSource) {
                    findings.append(LintFinding(message: "entities.\(typeName): no export named \"\(spec.provider)\" found."))
                }
            }
        }

        return findings
    }

    // Lint-only check — a lightweight text scan, not a full compile. Providers must be
    // `export const name = ...` (matching widget.ts's size-export convention); esmToCJS's
    // named-export handling doesn't recognize `export function name() {}`.
    private static func hasExport(named name: String, in source: String) -> Bool {
        let pattern = "export\\s+(const|let|var)\\s+\(NSRegularExpression.escapedPattern(for: name))\\b"
        return source.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - Self-check

    #if DEBUG
    @discardableResult
    static func runSelfCheck() -> Bool {
        var failures: [String] = []
        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            if !condition() { failures.append(name) }
        }
        func param(_ name: String, _ type: LoomConfig.IntentParam.ParamType, _ description: String?) -> LoomConfig.IntentParam {
            LoomConfig.IntentParam(name: name, type: type, description: description, optional: false)
        }

        // A fully clean project — proper description, every input described, entity provider
        // present — must produce zero findings. As important as catching real problems.
        var clean = LoomConfig(name: "Clean", description: "Fetches today's weather.")
        clean.intent = LoomConfig.IntentConfig(inputs: [param("city", .string, "City name")])
        clean.entities = ["note": LoomConfig.EntityType(displayName: "Note", fields: [:], provider: "noteProvider")]
        let cleanSource = "export const noteProvider = function() { return []; };"
        check("clean.zeroFindings", SiriLint.check(config: clean, rawSource: cleanSource).isEmpty)

        // Empty description.
        let empty = LoomConfig(name: "X", description: "")
        check("empty.flagsMissingDescription", SiriLint.check(config: empty, rawSource: "").count == 1)

        // Untouched scaffolded placeholder.
        let placeholder = LoomConfig(name: "X", description: "A new Loom script.")
        check("placeholder.flagged", SiriLint.check(config: placeholder, rawSource: "").count == 1)

        // Undescribed input field.
        var undescribed = LoomConfig(name: "X", description: "Does a thing.")
        undescribed.intent = LoomConfig.IntentConfig(inputs: [param("city", .string, nil)])
        check("undescribed.flagged", SiriLint.check(config: undescribed, rawSource: "").count == 1)

        // Over the string-slot bound (4).
        var overflow = LoomConfig(name: "X", description: "Does a thing.")
        overflow.intent = LoomConfig.IntentConfig(inputs: (1...5).map { param("s\($0)", .string, "d") })
        let overflowFindings = SiriLint.check(config: overflow, rawSource: "")
        check("overflow.flagged", overflowFindings.contains { $0.message.contains("only 4 supported") })

        // Entity provider export missing from source.
        var missingProvider = LoomConfig(name: "X", description: "Does a thing.")
        missingProvider.entities = ["note": LoomConfig.EntityType(displayName: "Note", fields: [:], provider: "noteProvider")]
        check("missingProvider.flagged", SiriLint.check(config: missingProvider, rawSource: "// no export here").count == 1)

        if failures.isEmpty {
            print("[SiriLint] self-check passed")
        } else {
            print("[SiriLint] self-check FAILED: \(failures.joined(separator: ", "))")
        }
        return failures.isEmpty
    }
    #endif
}
