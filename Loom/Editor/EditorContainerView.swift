import SwiftUI

struct EditorContainerView: View {
    let project: LoomProject
    @State private var presenter: ProjectFolderPresenter?
    @State private var reloadTrigger = UUID()
    @State private var viewModel = ScriptRunnerViewModel()
    @State private var isConsoleExpanded = false
    private let consoleHeight: CGFloat = 200

    var body: some View {
        VStack(spacing: 0) {
            // Editor
            ZStack(alignment: .bottom) {
                EditorView(
                    fileURL: project.mainFileURL,
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
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
            reloadTrigger = UUID()
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
