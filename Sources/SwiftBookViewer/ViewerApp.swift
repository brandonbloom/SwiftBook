#if os(macOS)
    import AppKit
    import SwiftUI

    /// The SwiftBook viewer: every story of one package, rendered in a process of its own.
    ///
    /// Usually started by `swiftbook view`. It opens the package in `SWIFTBOOK_PACKAGE`, or else
    /// the current directory. With `SWIFTBOOK_VIEWER_SNAPSHOT` set to a path, it draws its window
    /// to that PNG once the first story has rendered, and quits: a smoke test that needs no
    /// screen. The model's state goes beside it as JSON. For snapshots of particular states,
    /// `SWIFTBOOK_VIEWER_STORY` selects a story by ID, and `SWIFTBOOK_VIEWER_COMPARE` sets the
    /// comparison as `<mode>:<dimension>`, for example `grid:revision`.
    ///
    /// It takes no arguments: AppKit treats them as files to open, and SwiftUI then opens no
    /// window.
    @main struct ViewerApp: App {
        @NSApplicationDelegateAdaptor private var delegate: ViewerDelegate
        @State private var model: ViewerModel
        private let snapshot: URL?
        private let story: String?
        private let compare: String?

        init() {
            let environment = ProcessInfo.processInfo.environment
            snapshot = environment["SWIFTBOOK_VIEWER_SNAPSHOT"].map { URL(filePath: $0) }
            story = environment["SWIFTBOOK_VIEWER_STORY"]
            compare = environment["SWIFTBOOK_VIEWER_COMPARE"]
            let package = URL(
                filePath: environment["SWIFTBOOK_PACKAGE"]
                    ?? FileManager.default.currentDirectoryPath,
                directoryHint: .isDirectory)
            _model = State(initialValue: ViewerModel(package: package.standardizedFileURL))
        }

        /// Waits for the canvas to settle, draws the window to `url`, and quits.
        @MainActor static func snapshot(_ model: ViewerModel, to url: URL) async {
            // Let rendering ahead and the comparisons with the basis finish too, within reason.
            for _ in 0..<600
            where !model.pending.isEmpty || model.statuses.values.contains(.pending) {
                try? await Task.sleep(for: .milliseconds(50))
            }
            for _ in 0..<600
            where model.isRenderingSelection
                || model.cells.contains(where: { model.state(of: $0) == .loading })
            {
                try? await Task.sleep(for: .milliseconds(50))
            }
            try? await Task.sleep(for: .milliseconds(500))
            if let view = NSApplication.shared.windows.first(where: \.isVisible)?.contentView,
                let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
            }
            // The drawing misses vibrant content, such as the sidebar's text, so the model's state
            // goes beside it for checking.
            try? JSONEncoder().encode(model.summary).write(
                to: url.deletingPathExtension().appendingPathExtension("json"))
            NSApplication.shared.terminate(nil)
        }

        var body: some Scene {
            WindowGroup("SwiftBook") {
                ContentView(model: model)
                    .frame(minWidth: 800, minHeight: 500)
                    .task {
                        // Scripted sessions watch for stalls, once the window is up: launching
                        // isn't one.
                        if snapshot != nil { MainThreadWatchdog.shared.start() }
                        await model.start()
                        if let story { model.selectedNode = story }
                        if let compare {
                            let parts = compare.split(separator: ":").map(String.init)
                            if let mode = parts.first.flatMap(ViewerModel.CompareMode.init) {
                                model.compareMode = mode
                            }
                            if let dimension = parts.dropFirst().first.flatMap(
                                ViewerModel.CompareDimension.init)
                            {
                                model.compareDimension = dimension
                            }
                        }
                        // Rebuild on edits for as long as the window is open.
                        let watcher = FileWatcher(directory: model.package) { paths in
                            Task { @MainActor in model.filesChanged(paths) }
                        }
                        defer { watcher.stop() }
                        if let snapshot { await Self.snapshot(model, to: snapshot) }
                        // The task, and so the watcher, lasts until the window closes.
                        while !Task.isCancelled { try? await Task.sleep(for: .seconds(3600)) }
                    }
            }
            .defaultLaunchBehavior(.presented)
        }
    }

    /// Makes a plain executable behave like an app.
    ///
    /// Quitting needs no cleanup: a renderer exits when its input closes, which happens when the
    /// viewer does.
    final class ViewerDelegate: NSObject, NSApplicationDelegate {

        func applicationWillFinishLaunching(_ notification: Notification) {
            // Launched from a terminal rather than as a bundle, the app would otherwise have no
            // Dock icon or menu bar.
            NSApplication.shared.setActivationPolicy(.regular)
        }

        func applicationDidFinishLaunching(_ notification: Notification) {
            NSApplication.shared.activate()
        }

        func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
            true
        }

    }
#else
    @main enum ViewerApp {
        static func main() {}
    }
#endif
