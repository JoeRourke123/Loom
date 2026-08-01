import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

// Builds CSSearchableItems from a project's entity provider output — see
// ModuleBundler.executionFooter's entity-collection pass, which calls each configured
// provider() export after a successful run and serialises the results to
// __loom_entities_result__. Records are keyed "<project>:<type>:<recordId>" so re-indexing
// overwrites rather than duplicates; deletion is scoped per-project via domainIdentifier.
//
// Record shape (no prior art — designed for this milestone): each provider-returned record is
// a plain object `{ id, ...fields }`, decoded here via JSONSerialization rather than Codable
// since field shapes are entirely author-defined and dynamic — matching how this codebase
// already handles other JS-originated dynamic data (Loom.db rows, ctx.input).
enum EntityIndexer {
    nonisolated static func index(project: LoomProject, entitiesJSON: String, config: LoomConfig) {
        guard let data = entitiesJSON.data(using: .utf8),
              let byType = try? JSONSerialization.jsonObject(with: data) as? [String: [[String: Any]]]
        else { return }

        var items: [CSSearchableItem] = []
        for (typeName, records) in byType {
            guard let spec = config.entities?[typeName] else { continue }
            for record in records {
                guard let id = record["id"] as? String else { continue }

                let attributes = CSSearchableItemAttributeSet(contentType: .content)
                attributes.title = (record["title"] as? String) ?? (record["name"] as? String) ?? id
                attributes.contentDescription = spec.displayName
                attributes.keywords = record.values.compactMap { value -> String? in
                    switch value {
                    case let s as String: return s
                    case let n as NSNumber: return n.stringValue
                    default: return nil
                    }
                }

                items.append(CSSearchableItem(
                    uniqueIdentifier: "\(project.name):\(typeName):\(id)",
                    domainIdentifier: project.name,
                    attributeSet: attributes
                ))
            }
        }

        guard !items.isEmpty else { return }
        CSSearchableIndex.default().indexSearchableItems(items) { _ in }
    }

    nonisolated static func deleteAll(forProject projectName: String) {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [projectName]) { _ in }
    }
}
