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
            .alert(
                "Couldn't open the story",
                isPresented: Binding(
                    get: { model.openError != nil }, set: { if !$0 { model.openError = nil } })
            ) {
                Button("OK") {}
            } message: {
                Text(model.openError ?? "")
            }
            .toolbar {
                ToolbarItemGroup(placement: .principal) {
                    CompareControls(model: model)
                }
                ToolbarItem {
                    ControlGroup {
                        Button {
                            model.zoomOut()
                        } label: {
                            Label("Zoom Out", systemImage: "minus.magnifyingglass")
                        }
                        .keyboardShortcut("-")
                        .help("Zoom out")
                        Button("\(Int((model.zoom * 100).rounded()))%") { model.zoom = 1 }
                            .keyboardShortcut("0")
                            .monospacedDigit()
                            .help("Actual size")
                        Button {
                            model.zoomIn()
                        } label: {
                            Label("Zoom In", systemImage: "plus.magnifyingglass")
                        }
                        .keyboardShortcut("=")
                        .help("Zoom in")
                    } label: {
                        Label("Zoom", systemImage: "magnifyingglass")
                    }
                }
                ToolbarSpacer(.fixed)
                ToolbarItem {
                    Button {
                        model.openInteractively()
                    } label: {
                        Label("Open Interactively", systemImage: "macwindow.and.cursorarrow")
                    }
                    .keyboardShortcut("o")
                    .disabled(model.status != .ready || model.selection == nil)
                    .help("Open the story live in a window of its own (or double-click a cell)")
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
            }
        }
    }

    /// The toolbar's comparison mode (A), comparison dimension (B), and dimension values (C).
    struct CompareControls: View {
        @Bindable var model: ViewerModel

        private var comparing: Bool { model.compareMode != .single }

        var body: some View {
            Picker("Layout", selection: $model.compareMode) {
                Label("Single", systemImage: "rectangle").tag(ViewerModel.CompareMode.single)
                Label("2-up", systemImage: "rectangle.split.2x1").tag(ViewerModel.CompareMode.twoUp)
                Label("Grid", systemImage: "square.grid.2x2").tag(ViewerModel.CompareMode.grid)
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .help("Comparison mode")
            Picker("Compare", selection: $model.compareDimension) {
                Text("Color Scheme").tag(ViewerModel.CompareDimension.appearance)
                Text("Layout Direction").tag(ViewerModel.CompareDimension.layoutDirection)
                Text("Revision").tag(ViewerModel.CompareDimension.revision)
            }
            .pickerStyle(.menu)
            .fixedSize()
            .disabled(!comparing)
            .help("What to compare across")
            Picker("Appearance", selection: $model.appearance) {
                Label("Light", systemImage: "sun.max").tag(RenderEnvironment.Appearance.light)
                Label("Dark", systemImage: "moon").tag(RenderEnvironment.Appearance.dark)
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .disabled(comparing && model.compareDimension == .appearance)
            .help("Color scheme")
            Picker("Layout Direction", selection: $model.layoutDirection) {
                Label("Left to Right", systemImage: "text.alignleft").tag(
                    LayoutDirection.leftToRight)
                Label("Right to Left", systemImage: "text.alignright").tag(
                    LayoutDirection.rightToLeft)
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .disabled(comparing && model.compareDimension == .layoutDirection)
            .help("Layout direction")
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
                    List(selection: $model.selectedNode) {
                        ForEach(model.sidebarRows) { row in
                            SidebarRowView(row: row, model: model).tag(row.id)
                        }
                    }
                    // Arrow keys work as in Finder's outline: left collapses or goes up,
                    // right expands or goes in.
                    .onKeyPress(.leftArrow) {
                        model.moveLeft()
                        return .handled
                    }
                    .onKeyPress(.rightArrow) {
                        model.moveRight()
                        return .handled
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

    /// A row of the sidebar. Clicking anywhere on a module or group's row expands or collapses
    /// it, not just its disclosure arrow.
    struct SidebarRowView: View {
        let row: ViewerModel.SidebarRow
        @Bindable var model: ViewerModel

        var body: some View {
            HStack(spacing: 4) {
                if row.node.children != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(model.isExpanded(row.id) ? 90 : 0))
                        .frame(width: 12)
                    Text(row.node.title).foregroundStyle(.secondary)
                    Spacer()
                } else {
                    Color.clear.frame(width: 12, height: 1)
                    Text(row.node.title)
                    Spacer()
                    if let story = row.node.story {
                        StatusBadge(status: model.statuses[story] ?? .pending)
                    }
                }
            }
            .padding(.leading, Double(row.depth) * 14)
            .contentShape(Rectangle())
            .onTapGesture {
                if row.node.children != nil {
                    model.selectedNode = row.id
                    model.toggleExpanded(row.id)
                } else {
                    model.selectedNode = row.id
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
                        Cells(model: model, story: story)
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

    /// The canvas's cells, laid out per the comparison mode. Pinching zooms them all.
    struct Cells: View {
        @Bindable var model: ViewerModel
        let story: StoryID
        @State private var pinchStart: Double?

        var body: some View {
            let rows = model.cellRows
            let showsTitles = rows.count > 1 || (rows.first?.count ?? 0) > 1
            Grid(horizontalSpacing: 1, verticalSpacing: 1) {
                ForEach(rows, id: \.first?.id) { row in
                    GridRow {
                        ForEach(row) { cell in
                            CellView(
                                cell: cell, model: model, story: story, showsTitle: showsTitles)
                        }
                    }
                }
            }
            .background(.separator)
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        let start = pinchStart ?? model.zoom
                        pinchStart = start
                        model.zoom = min(8, max(0.25, start * value.magnification))
                    }
                    .onEnded { _ in pinchStart = nil })
        }
    }

    /// One image on the canvas. The cell under the pointer leads scrolling, and the others
    /// follow it.
    struct CellView: View {
        let cell: ViewerModel.Cell
        @Bindable var model: ViewerModel
        let story: StoryID
        let showsTitle: Bool
        @State private var position = ScrollPosition()
        @State private var hovering = false

        var body: some View {
            VStack(spacing: 0) {
                if showsTitle {
                    HStack {
                        Text(cell.title).font(.headline)
                        Spacer()
                        if let comparison = model.comparison(of: cell) {
                            ComparisonText(comparison: comparison)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.bar)
                }
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background)
            }
            .onHover { hovering = $0 }
            .onTapGesture(count: 2) { model.openInteractively(cell.variant) }
        }

        @ViewBuilder private var content: some View {
            switch model.state(of: cell) {
            case .image(let image):
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(model.zoom >= 2 ? .none : .high)
                        .frame(
                            width: image.size.width * model.zoom,
                            height: image.size.height * model.zoom
                        )
                        .border(.separator)
                        .padding(24)
                }
                .defaultScrollAnchor(.center)
                .scrollPosition($position)
                .onScrollGeometryChange(for: CGPoint.self) {
                    $0.contentOffset
                } action: {
                    _, offset in
                    if hovering, model.panOffset != offset { model.panOffset = offset }
                }
                .onChange(of: model.panOffset) { _, offset in
                    if !hovering { position.scrollTo(point: offset) }
                }
            case .failed(let message):
                ErrorText(title: "Couldn't render \(story.name)", message: message)
            case .loading:
                ProgressStatus(
                    text: {
                        switch cell.content {
                        case .render: "Rendering \(story.name)…"
                        case .reference: "Reading the reference…"
                        case .diff: "Comparing…"
                        }
                    }())
            case .empty(let reason):
                Text(reason).foregroundStyle(.secondary)
            }
        }
    }

    /// A comparison's diff metrics, in brief.
    struct ComparisonText: View {
        let comparison: ViewerModel.Comparison

        var body: some View {
            Group {
                if !comparison.sizesMatch {
                    Text("Sizes differ").foregroundStyle(.orange)
                } else if comparison.maxDeltaE == 0 {
                    Text("Identical")
                } else {
                    Text(
                        "\(comparison.changedPixelRatio.formatted(.percent.precision(.fractionLength(0...2)))) changed · ΔE \(comparison.maxDeltaE.formatted(.number.precision(.fractionLength(1))))"
                    )
                    .foregroundStyle(comparison.matches ? Color.secondary : Color.orange)
                }
            }
            .font(.callout)
            .monospacedDigit()
            .help(
                comparison.matches
                    ? "Within tolerance of the reference"
                    : "Differs from the reference: changed pixels and the largest perceptual difference"
            )
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
