import SwiftUI
import MarkdownUI

struct AssistantPanelView: View {
    let project: LoomProject
    let isExpanded: Bool
    @State private var session: AssistantSession
    @State private var inputText = ""
    @State private var isSettingsShowing = false
    @FocusState private var isInputFocused: Bool
    private var providerStore = AIProviderStore.shared

    init(project: LoomProject, isExpanded: Bool = true) {
        self.project = project
        self.isExpanded = isExpanded
        _session = State(initialValue: AssistantStore.shared.session(for: project))
    }

    var body: some View {
        Group {
            if providerStore.providers.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    toolbar
                    Divider()
                    messageList
                    Divider()
                    inputBar
                }
            }
        }
        .onAppear(perform: consumePendingPrompt)
        .sheet(isPresented: $isSettingsShowing) {
            NavigationStack { SettingsView() }
        }
    }

    // Mirrors ConsoleView's toolbar so the two panels line up when switching tabs. Revert lives
    // here rather than above the input field: it's a rarely-used, destructive action, and down
    // there it sat directly under the send button and moved as the token count appeared.
    private var toolbar: some View {
        HStack {
            let totalTokens = session.tokensUsed.input + session.tokensUsed.output
            if totalTokens > 0 {
                Text("\(totalTokens) tokens")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if session.hasSnapshot {
                Button(role: .destructive) {
                    session.revertLastChanges()
                } label: {
                    Label("Revert AI Changes", systemImage: "arrow.uturn.backward")
                        .font(.caption)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minHeight: 30)
        .background(.bar)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No AI provider configured")
                .font(.subheadline.bold())
            Button("Open Settings") { isSettingsShowing = true }
                .font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(session.displayMessages) { message in
                        messageRow(message).id(message.id)
                    }
                    // Shown while streaming but before the first text lands (the model may spend
                    // several seconds on tool calls or reasoning first) — without it the panel
                    // looks frozen. Suppressed once text starts arriving, since the streaming
                    // text is itself the progress indicator at that point.
                    if session.isStreaming, session.displayMessages.last?.kind != .assistantText {
                        thinkingIndicator.id(Self.thinkingRowID)
                    }
                    if let error = session.lastError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.top, 2)
                    }
                }
                .padding(10)
            }
            .onChange(of: session.isStreaming) { _, streaming in
                if streaming { proxy.scrollTo(Self.thinkingRowID, anchor: .bottom) }
            }
            .onChange(of: session.displayMessages.count) { _, _ in
                if let last = session.displayMessages.last?.id {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
            // Count alone only fires on a new row — without this, the view stops following once
            // text starts streaming into the *existing* last row, so it looks stalled/finished
            // even while more is still arriving.
            .onChange(of: session.displayMessages.last?.text) { _, _ in
                if let last = session.displayMessages.last?.id {
                    withAnimation(.linear(duration: 0.1)) {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
    }

    private static let thinkingRowID = "loom.assistant.thinking"

    private var thinkingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Thinking…")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    @ViewBuilder
    private func messageRow(_ message: AssistantSession.DisplayMessage) -> some View {
        switch message.kind {
        case .userText:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .padding(8)
                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            }
        case .assistantText:
            HStack {
                Markdown(message.text)
                    .textSelection(.enabled)
                Spacer(minLength: 20)
            }
        case .toolCall:
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(message.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                // Capsule-in-a-container rather than .roundedBorder — the stock style renders as a
                // hard-edged rectangle that reads as unfinished next to the rounded panel above it.
                TextField("Describe what you want…", text: $inputText, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(.tertiarySystemFill))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(isInputFocused ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1.5)
                    )
                    .focused($isInputFocused)
                    .submitLabel(.send)
                    .onSubmit(sendMessage)

                Group {
                    if session.isStreaming {
                        Button { session.stop() } label: {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 30))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Stop generating")
                    } else {
                        Button(action: sendMessage) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.4))
                        }
                        .disabled(!canSend)
                        .accessibilityLabel("Send")
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: session.isStreaming)
                .padding(.bottom, 1)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendMessage() {
        let text = inputText
        inputText = ""
        session.send(text)
    }

    private func consumePendingPrompt() {
        if let prompt = AssistantStore.shared.consumePendingPrompt(for: project.name) {
            session.send(prompt)
        }
    }
}
