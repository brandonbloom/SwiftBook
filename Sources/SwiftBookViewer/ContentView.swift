#if os(macOS)
    import SwiftBookCore
    import SwiftUI

    struct ContentView: View {
        @Bindable var model: ViewerModel

        var body: some View {
            NavigationSplitView {
                Sidebar(model: model)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 260)
            } detail: {
                Canvas(model: model)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Appearance", selection: $model.appearance) {
                        Text("Light").tag(RenderEnvironment.Appearance.light)
                        Text("Dark").tag(RenderEnvironment.Appearance.dark)
                    }
                    .pickerStyle(.segmented)
                    .help("Color scheme")
                }
                ToolbarItem {
                    Button {
                        Task { await model.reload() }
                    } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r")
                    .disabled(model.status != .ready || model.isRebuilding)
                    .help("Build the package again and re-render")
                }
                ToolbarItem {
                    // Comparison mode and dimension come with toolbar-compare.
                    Menu("Compare", systemImage: "rectangle.split.2x1") {
                        Text("Single")
                    }
                    .disabled(true)
                    .help("Comparison (coming soon)")
                }
            }
        }
    }

    struct Sidebar: View {
        @Bindable var model: ViewerModel

        var body: some View {
            Group {
                switch model.status {
                case .building:
                    ProgressStatus(text: "Building the renderer…")
                case .listing:
                    ProgressStatus(text: "Finding stories…")
                case .failed:
                    ContentUnavailableView(
                        "No stories", systemImage: "exclamationmark.triangle",
                        description: Text("The renderer couldn't start."))
                case .ready:
                    List(selection: $model.selection) {
                        OutlineGroup(model.visibleTree, children: \.children) { node in
                            if let story = node.story {
                                HStack {
                                    Text(node.title)
                                    Spacer()
                                    StatusBadge(status: model.statuses[story] ?? .pending)
                                }
                                .tag(story)
                            } else {
                                Text(node.title).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .searchable(text: $model.searchText, placement: .sidebar, prompt: "Stories")
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if model.basis != nil {
                            BasisBar(model: model)
                        }
                    }
                }
            }
        }
    }

    /// Chooses what the sidebar compares against, and whether it shows only changes.
    struct BasisBar: View {
        @Bindable var model: ViewerModel
        @State private var askingForRevision = false
        @State private var revision = ""

        var body: some View {
            HStack(spacing: 6) {
                Menu {
                    ForEach([ViewerBasis.uncommitted, .lastCommit, .branch], id: \.self) { basis in
                        Button(basis.title) { model.basis = basis }
                    }
                    Divider()
                    Button("Revision…") { askingForRevision = true }
                } label: {
                    Text("Against: \(model.basis?.title ?? "")")
                        .lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(
                    model.historyError ?? model.basisRevision.map {
                        "Comparing with \($0.prefix(9))"
                    } ?? "")
                Spacer()
                Toggle(isOn: $model.showsChangedOnly) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .toggleStyle(.button)
                .buttonStyle(.borderless)
                .help("Show only stories that changed")
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .alert("Compare with a revision", isPresented: $askingForRevision) {
                TextField("Branch, tag, or commit", text: $revision)
                Button("Compare") {
                    let trimmed = revision.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { model.basis = .revision(trimmed) }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    /// A story's change against the basis, as a small symbol.
    struct StatusBadge: View {
        let status: ChangeStatus

        var body: some View {
            switch status {
            case .pending, .unchanged:
                EmptyView()
            case .sourceChanged:
                Image(systemName: "circle.dotted").foregroundStyle(.orange)
                    .help("The source changed; rendering to see whether the image did")
            case .changed:
                Image(systemName: "circle.fill").foregroundStyle(.orange)
                    .imageScale(.small)
                    .help("Changed")
            case .new:
                Image(systemName: "plus.circle.fill").foregroundStyle(.green)
                    .help("New: no reference at the basis")
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    .help("Didn't render")
            }
        }
    }

    struct ProgressStatus: View {
        let text: String

        var body: some View {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(text).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    struct Canvas: View {
        let model: ViewerModel

        var body: some View {
            VStack(spacing: 0) {
                if let error = model.buildError {
                    BuildErrorBanner(message: error)
                }
                Group {
                    if case .failed(let message) = model.status {
                        ErrorText(title: "The renderer couldn't start", message: message)
                    } else if let story = model.selection {
                        switch model.currentRender {
                        case .image(let image)?:
                            ScrollView([.horizontal, .vertical]) {
                                Image(nsImage: image)
                                    .border(.separator)
                                    .padding(24)
                            }
                            .defaultScrollAnchor(.center)
                        case .failed(let message)?:
                            ErrorText(title: "Couldn't render \(story.name)", message: message)
                        case nil:
                            ProgressStatus(text: "Rendering \(story.name)…")
                        }
                    } else {
                        ContentUnavailableView(
                            "Select a story", systemImage: "rectangle.on.rectangle")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topTrailing) {
                    // An earlier render stays up while its replacement renders.
                    if model.currentRender != nil, model.isRenderingSelection || model.isRebuilding
                    {
                        ProgressView().controlSize(.small).padding(12)
                    }
                }
            }
            .navigationTitle(model.selection?.name ?? model.package.lastPathComponent)
            .navigationSubtitle(model.selection.map { "\($0.module) › \($0.group)" } ?? "")
        }
    }

    /// The last rebuild's failure, above the last good renders.
    struct BuildErrorBanner: View {
        let message: String
        @State private var expanded = false

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    expanded.toggle()
                } label: {
                    Label(
                        "The build failed. Showing the last good renders.",
                        systemImage: "exclamationmark.triangle.fill")
                }
                .buttonStyle(.plain)
                if expanded {
                    ScrollView {
                        Text(message).font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 160)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.yellow.opacity(0.2))
        }
    }

    struct ErrorText: View {
        let title: String
        let message: String

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Label(title, systemImage: "exclamationmark.triangle").font(.headline)
                    Text(message).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
#endif
