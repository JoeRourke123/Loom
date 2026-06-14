import SwiftUI

struct SettingsView: View {
    @State private var claudeKey = ""
    @State private var geminiKey = ""

    var body: some View {
        Form {
            Section("API Keys") {
                SecureField("Claude API Key", text: $claudeKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Gemini API Key", text: $geminiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .navigationTitle("Settings")
        .onAppear(perform: loadKeys)
        .onChange(of: claudeKey) { _, new in
            new.isEmpty
                ? KeychainManager.delete(service: KeychainManager.claudeAPIKeyService)
                : KeychainManager.save(new, service: KeychainManager.claudeAPIKeyService)
        }
        .onChange(of: geminiKey) { _, new in
            new.isEmpty
                ? KeychainManager.delete(service: KeychainManager.geminiAPIKeyService)
                : KeychainManager.save(new, service: KeychainManager.geminiAPIKeyService)
        }
    }

    private func loadKeys() {
        claudeKey = KeychainManager.load(service: KeychainManager.claudeAPIKeyService) ?? ""
        geminiKey = KeychainManager.load(service: KeychainManager.geminiAPIKeyService) ?? ""
    }
}
