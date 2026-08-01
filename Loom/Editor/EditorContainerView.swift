import SwiftUI

struct EditorContainerView: View {
    let project: LoomProject
    @State private var presenter: ProjectFolderPresenter?
    @State private var reloadTrigger = UUID()
    @State private var viewModel = ScriptRunnerViewModel()
    @State private var isConsoleExpanded = false
    @State private var isWidgetPreviewShowing = false
    @State private var widgetPreviewRefreshToken = UUID()
    @State private var projectFiles: [URL] = []
    @State private var selectedFileURL: URL? = nil
    @State private var isNewFileShowing = false
    @State private var isDeletingFile = false
    private let consoleHeight: CGFloat = 200

    private var activeFileURL: URL { selectedFileURL ?? project.mainFileURL }
    private var activeFileName: String { activeFileURL.lastPathComponent }
    private var existingFileNames: Set<String> { Set(projectFiles.map(\.lastPathComponent)) }
    private var hasWidget: Bool { existingFileNames.contains("widget.ts") }

    var body: some View {
        VStack(spacing: 0) {
            // Editor
            ZStack(alignment: .bottom) {
                EditorView(
                    fileURL: activeFileURL,
                    externalReloadTrigger: reloadTrigger,
                    onCompileError: { viewModel.compileError = $0 }
                )

                // Compile error banner
                if let err = viewModel.compileError {
                    CompileErrorBanner(error: err) {
                        viewModel.compileError = nil
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 8)
                    .padding(.horizontal, 12)
                }
            }

            // Console panel
            if isConsoleExpanded {
                Divider()
                ConsoleView(session: viewModel.currentSession)
                    .frame(height: consoleHeight)
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.spring(duration: 0.25), value: isConsoleExpanded)
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
                // Console toggle with badge
                Button {
                    isConsoleExpanded.toggle()
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: isConsoleExpanded ? "chevron.down.square.fill" : "chevron.up.square")
                        if let count = viewModel.currentSession?.logs.count, count > 0, !isConsoleExpanded {
                            Text("\(min(count, 99))")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(2)
                                .background(Color.accentColor, in: Capsule())
                                .offset(x: 6, y: -6)
                        }
                    }
                }

                // Widget preview button (only visible when project has widget.ts)
                if hasWidget {
                    Button {
                        widgetPreviewRefreshToken = UUID()
                        isWidgetPreviewShowing = true
                    } label: {
                        Image(systemName: "rectangle.on.rectangle")
                    }
                }

                // Run button
                Button {
                    isConsoleExpanded = true
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
        }
        .onDisappear {
            presenter = nil
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
            if wasRunning, !isRunning, hasWidget {
                widgetPreviewRefreshToken = UUID()
            }
        }
        .sheet(isPresented: $isWidgetPreviewShowing) {
            NavigationStack {
                WidgetPreviewPanel(project: project, refreshToken: widgetPreviewRefreshToken)
                    .navigationTitle("Widget Preview")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isWidgetPreviewShowing = false }
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
            .filter { $0.pathExtension == "ts" }
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
