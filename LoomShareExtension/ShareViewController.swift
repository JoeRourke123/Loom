import UIKit
import Social
import SwiftUI
import UniformTypeIdentifiers

// Builds on Xcode's SLComposeServiceViewController template (Apple's native compose-sheet UI
// for share extensions) rather than a custom SwiftUI root — configurationItems() gives a
// native "Project" picker row for free, matching how system share extensions (e.g. Twitter's)
// let you pick an account/audience via the same mechanism. No JSC/SWC runs here (see
// ADR-004/ADR-009) — this only stages content and hands off to the main app via loom://share.
class ShareViewController: SLComposeServiceViewController {
    private var selectedProjectName: String?
    private var availableProjects: [String] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Loom"
        placeholder = "Add a note (optional)"
        availableProjects = Self.loadProjectNames()
        selectedProjectName = availableProjects.first
    }

    override func isContentValid() -> Bool {
        selectedProjectName != nil
    }

    override func configurationItems() -> [Any]! {
        guard let item = SLComposeSheetConfigurationItem() else { return [] }
        item.title = "Project"
        item.value = availableProjects.isEmpty ? "No Loom projects" : (selectedProjectName ?? "Choose…")
        item.tapHandler = { [weak self] in
            self?.presentProjectPicker()
        }
        return [item]
    }

    private func presentProjectPicker() {
        guard !availableProjects.isEmpty else { return }
        let picker = ProjectPickerView(projects: availableProjects, selected: selectedProjectName) { [weak self] name in
            guard let self else { return }
            selectedProjectName = name
            navigationController?.popViewController(animated: true)
            reloadConfigurationItems()
            validateContent()
        }
        pushConfigurationViewController(UIHostingController(rootView: picker))
    }

    override func didSelectPost() {
        guard let projectName = selectedProjectName else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }

        extractContent { [weak self] type, text, imageData in
            guard let self else { return }

            var queryItems = [
                URLQueryItem(name: "project", value: projectName),
                URLQueryItem(name: "type", value: type),
            ]

            if let imageData {
                if let token = Self.stage(imageData) {
                    queryItems.append(URLQueryItem(name: "token", value: token))
                }
            } else {
                let text = text ?? ""
                if text.utf8.count > 1500, let data = text.data(using: .utf8), let token = Self.stage(data) {
                    queryItems.append(URLQueryItem(name: "token", value: token))
                } else {
                    queryItems.append(URLQueryItem(name: "value", value: text))
                }
            }

            var components = URLComponents()
            components.scheme = "loom"
            components.host = "share"
            components.queryItems = queryItems

            guard let url = components.url else {
                self.extensionContext?.completeRequest(returningItems: nil)
                return
            }
            self.extensionContext?.open(url) { _ in
                self.extensionContext?.completeRequest(returningItems: nil)
            }
        }
    }

    // Loads the first attachment as a URL, image, or plain text, in that priority order —
    // matching the { type: 'url'|'text'|'image', value } shape Loom.share.input() exposes.
    // Falls back to the compose box's typed text if there's no attachment at all.
    private func extractContent(completion: @escaping (_ type: String, _ text: String?, _ imageData: Data?) -> Void) {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first
        else {
            completion("text", contentText, nil)
            return
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier) { data, _ in
                completion("url", (data as? URL)?.absoluteString ?? "", nil)
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.image.identifier) { data, _ in
                var imageData: Data?
                if let url = data as? URL {
                    imageData = try? Data(contentsOf: url)
                } else if let image = data as? UIImage {
                    imageData = image.jpegData(compressionQuality: 0.85)
                } else if let raw = data as? Data {
                    imageData = raw
                }
                completion("image", nil, imageData)
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { [weak self] data, _ in
                completion("text", (data as? String) ?? self?.contentText, nil)
            }
        } else {
            completion("text", contentText, nil)
        }
    }

    private static func loadProjectNames() -> [String] {
        guard let defaults = UserDefaults(suiteName: "group.uk.co.joerourke.loom"),
              let json = defaults.string(forKey: "loom.allProjects"),
              let data = json.data(using: .utf8),
              let names = try? JSONSerialization.jsonObject(with: data) as? [String]
        else { return [] }
        return names
    }

    // Stages data into the App Group container under a random token; DeepLinkHandler derives
    // the same path from just the token (group.uk.co.joerourke.loom, "share-<token>") — no
    // separate lookup needed.
    private static func stage(_ data: Data) -> String? {
        let token = UUID().uuidString
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.uk.co.joerourke.loom")?
            .appendingPathComponent("share-\(token)")
        else { return nil }
        guard (try? data.write(to: url)) != nil else { return nil }
        return token
    }
}

private struct ProjectPickerView: View {
    let projects: [String]
    let selected: String?
    let onSelect: (String) -> Void

    var body: some View {
        List(projects, id: \.self) { name in
            Button {
                onSelect(name)
            } label: {
                HStack {
                    Text(name)
                    Spacer()
                    if name == selected {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .foregroundStyle(.primary)
        }
    }
}
