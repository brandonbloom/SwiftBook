#if os(macOS)
    import AppKit
    import Testing

    @testable import SwiftBookCore

    @MainActor @Suite struct RenderWindowTests {
        @Test func neverSeesThePointer() {
            let window = MacRenderer.makeWindow(appearance: .light)
            defer { window.close() }
            #expect(window.ignoresMouseEvents)
            #expect(!window.acceptsMouseMovedEvents)
            // Far from every screen, so hover tracking can't find the pointer inside it.
            #expect(NSScreen.screens.allSatisfy { !$0.frame.intersects(window.frame) })
            #expect(!window.frame.contains(NSEvent.mouseLocation))
        }
    }
#endif
