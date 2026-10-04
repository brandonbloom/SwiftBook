#if os(macOS)
    import AppKit
    import SwiftUI

    /// Stories shown live in windows of their own, for someone to click, type, and scroll in.
    ///
    /// Unlike captures, they keep animations on, and they take the pointer and focus.
    @MainActor public enum InteractiveWindows {
        /// Set to order windows behind others without taking focus, for tests.
        public static let behindVariable = "SWIFTBOOK_INTERACTIVE_BEHIND"

        private static var shown: [(window: NSWindow, record: RendererWindow)] = []

        /// Shows `story` in `environment` in a new window, in front.
        public static func open(_ story: Story, in environment: RenderEnvironment) async throws {
            let view = AnyView(try await story.makeView().live(in: environment))
            let content: AnyView
            switch story.layout {
            case .device:
                content = AnyView(
                    view.frame(width: environment.deviceWidth, height: environment.deviceHeight))
            case .fixed(let width, let height):
                content = AnyView(view.frame(width: width, height: height))
            case .sizeThatFits:
                content = view
            }
            let window = NSWindow(
                contentViewController: NSHostingController(
                    rootView: content.background(Color(nsColor: .windowBackgroundColor))))
            window.title = story.id.name
            window.subtitle = "\(story.id.module) › \(story.id.group)"
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(
                named: environment.appearance == .dark ? .darkAqua : .aqua)
            shown.append(
                (window, RendererWindow(story: story.id.description, environment: environment)))
            window.center()
            if ProcessInfo.processInfo.environment[behindVariable] != nil {
                window.orderBack(nil)
                return
            }
            // A renderer is otherwise never seen. As an accessory it can show windows and take
            // focus, but gets no Dock tile.
            if NSApplication.shared.activationPolicy() == .prohibited {
                NSApplication.shared.setActivationPolicy(.accessory)
            }
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate()
        }

        /// The windows still open.
        public static var open: [RendererWindow] {
            shown.removeAll { !$0.window.isVisible }
            return shown.map(\.record)
        }
    }
#endif
