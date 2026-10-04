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
                        OutlineGroup(model.tree, children: \.children) { node in
                            if let story = node.story {
                                Text(node.title).tag(story)
                            } else {
                                Text(node.title).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
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
                    case .rendering?, nil:
                        ProgressStatus(text: "Rendering \(story.name)…")
                    }
                } else {
                    ContentUnavailableView("Select a story", systemImage: "rectangle.on.rectangle")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(model.selection?.name ?? model.package.lastPathComponent)
            .navigationSubtitle(model.selection.map { "\($0.module) › \($0.group)" } ?? "")
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
