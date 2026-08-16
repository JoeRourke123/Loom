import SwiftUI

struct EditorContainerView: View {
    let project: LoomProject
    @State private var presenter: ProjectFolderPresenter?
    @State private var reloadTrigger = UUID()
    @State private var viewModel = ScriptRunnerViewModel()
    @State private var panel = EditorPanelCoordinator.shared
    // Owned here, not by EditorView's Coordinator: long-press-for-docs needs a real SwiftUI
    // view in the real hierarchy to present a sheet from — a UIHostingController with no parent
    // view controller (which is what the accessory bar's hosting controller is) can't reliably
    // present one itself.
    @State private var suggestions = SuggestionEngine()
    @State private var projectFiles: [URL] = []
    @State private var selectedFileURL: URL? = nil
    @State private var isNewFileShowing = false
    @State private var isDeletingFile = false

    private var activeFileURL: URL { selectedFileURL ?? project.mainFileURL }
    private var activeFileName: String { activeFileURL.lastPathComponent }
    private var existingFileNames: Set<String> { Set(projectFiles.map(\.lastPathComponent)) }

    var body: some View {
        // GeometryReader stays *outside* the ignoresSafeArea below so it still reports the real
        // bottom inset — with a tab bar accessory present that covers tab bar + strip + home
        // indicator, which is exactly the height the editor has to inset its content by.
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                EditorView(
                    fileURL: activeFileURL,
                    externalReloadTrigger: reloadTrigger,
                    bottomContentInset: geo.safeAreaInsets.bottom,
                    onCompileError: { viewModel.compileError = $0 },
                    suggestions: suggestions
                )
                // .container alone left .keyboard un-ignored, so when the keyboard rose SwiftUI
                // both shrank this view's frame AND fed the same height into
                // bottomContentInset below (geo.safeAreaInsets.bottom is the union of container +
                // keyboard insets) — a double-count that grew a dead scroll region under the
                // keyboard. Ignoring .keyboard too means exactly one of those applies the inset.
                .ignoresSafeArea([.container, .keyboard], edges: .bottom)

                // Banner keeps the safe area so it floats above the bars rather than under them.
                if let err = viewModel.compileError {
                    CompileErrorBanner(error: err) {
                        viewModel.compileError = nil
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 8)
                    .padding(.horizontal, 12)
                }
            }
        }
        .animation(.spring(duration: 0.2), value: viewModel.compileError != nil)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // File switcher as principal (replaces nav title)
            ToolbarItem(placement: .principal) {
                Menu {
                    ForEach(projectFiles, id: \.self) { url in
                        Button {
                            if url != activeFileURL {
                                viewModel.compileError = nil
                                selectedFileURL = url
                                reloadTrigger = UUID()
                            }
                        } label: {
                            if url == activeFileURL {
                                Label(url.lastPathComponent, systemImage: "checkmark")
                            } else {
                                Text(url.lastPathComponent)
                            }
                        }
                    }
                    Divider()
                    Button {
                        isNewFileShowing = true
                    } label: {
                        Label("New File…", systemImage: "plus")
                    }
                    if activeFileName != "main.ts" {
                        Button(role: .destructive) {
                            isDeletingFile = true
                        } label: {
                            Label("Delete \(activeFileName)", systemImage: "trash")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(activeFileName)
                            .font(.headline)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                // Expands the Console/Siri/Assistant sheet. The collapsed strip is always present
                // as the tab bar accessory while an editor is open, so this only ever opens.
                Button {
                    panel.isExpanded.toggle()
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: panel.isExpanded ? "chevron.down.square.fill" : "chevron.up.square")
                        if let count = viewModel.currentSession?.logs.count, count > 0, !panel.isExpanded {
                            Text("\(min(count, 99))")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(2)
                                .background(Color.accentColor, in: Capsule())
                                .offset(x: 6, y: -6)
                        }
                    }
                }

                // Run button
                Button {
                    panel.tab = .console
                    panel.isExpanded = true
                    viewModel.run(project: project)
                } label: {
                    if viewModel.isRunning {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "play.fill")
                    }
                }
                .disabled(viewModel.isRunning)
            }
        }
        .onAppear {
            presenter = ProjectFolderPresenter(folderURL: project.folderURL)
            loadProjectFiles()
            panel.editorAppeared(project: project)
            panel.consoleSession = viewModel.currentSession
            if AssistantStore.shared.hasPendingPrompt(for: project.name) {
                panel.tab = .assistant
                panel.isExpanded = true
            }
        }
        .onDisappear {
            presenter = nil
            panel.editorDisappeared(project: project)
        }
        // The accessory strip lives outside this view, so it needs the live session pushed to it.
        .onChange(of: viewModel.currentSession?.runId) { _, _ in
            panel.consoleSession = viewModel.currentSession
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .loomProjectFolderChanged)
        ) { notification in
            guard let url = notification.userInfo?["folderURL"] as? URL,
                  url == project.folderURL
            else { return }
            loadProjectFiles()
            reloadTrigger = UUID()
        }
        .onChange(of: viewModel.isRunning) { wasRunning, isRunning in
            if wasRunning, !isRunning {
                panel.runFinished(project: project)
            }
        }
        .sheet(item: $suggestions.docPage) { page in
            NavigationStack {
                DocDetailView(page: page)
                    .navigationTitle(page.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { suggestions.docPage = nil }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isNewFileShowing) {
            NewFileSheet(project: project, existingNames: existingFileNames) { url in
                loadProjectFiles()
                selectedFileURL = url
                reloadTrigger = UUID()
            }
        }
        .confirmationDialog(
            "Delete \"\(activeFileName)\"?",
            isPresented: $isDeletingFile,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteActiveFile() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }

    private func deleteActiveFile() {
        guard activeFileName != "main.ts" else { return }
        try? FileManager.default.trashItem(at: activeFileURL, resultingItemURL: nil)
        selectedFileURL = nil
        viewModel.compileError = nil
        loadProjectFiles()
        reloadTrigger = UUID()
    }

    private func loadProjectFiles() {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: project.folderURL,
            includingPropertiesForKeys: nil
        ) else { return }
        let sorted = urls
            .filter { LoomProject.editableExtensions.contains($0.pathExtension.lowercased()) }
            .sorted {
                if $0.lastPathComponent == "main.ts" { return true }
                if $1.lastPathComponent == "main.ts" { return false }
                return $0.lastPathComponent < $1.lastPathComponent
            }
        projectFiles = sorted
        // If selected file was deleted, fall back to main.ts
        if let sel = selectedFileURL, !sorted.contains(sel) {
            selectedFileURL = nil
        }
    }
}

struct CompileErrorBanner: View {
    let error: CompileError
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(error.localizedDescription ?? "Compile error")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(3)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 4)
    }
}
