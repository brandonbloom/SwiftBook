import SwiftBookCore
import SwiftUI
import Testing

@testable import PreviewZoo

@MainActor @Suite struct AdapterTests {
    let stories = Story.all().filter { $0.id.module == "PreviewZoo" }

    func story(_ group: String, _ name: String) throws -> Story {
        try #require(stories.first { $0.id.group == group && $0.id.name == name })
    }

    @Test func namesEveryStory() {
        var expected = [
            "Arguments/Badge arguments / NEW", "Arguments/Badge arguments / SALE",
            "Arguments/Badge arguments / SOLD OUT",
            "Card/Card", "Card/Card 2", "Card/Card 3", "Card/Card (statements)",
            "Chrome/Sidebar selection", "Chrome/Accent avatar",
            "EdgeCases/Debug only", "EdgeCases/Slash / colon: and émoji 🌙", "EdgeCases/Duplicate",
            "EdgeCases/Duplicate 2",
            "Hazards/List", "Hazards/Text fields", "Hazards/Material and blur",
            "Hazards/Scroll view",
            "Hazards/Dates", "Hazards/Foundation-formatted date",
            "Layouts/Default layout", "Layouts/Size that fits", "Layouts/Fixed layout",
            "Layouts/Landscape",
            "Layouts/Combined traits",
        ]
        #if os(macOS)
            expected += [
                "PlatformViews/NSView", "PlatformViews/NSViewController",
                "PlatformViews/macOS only",
            ]
        #else
            expected += ["PlatformViews/UIView", "PlatformViews/UIViewController"]
        #endif
        expected += [
            "Previewable/Previewable state",
            "SharedContext/Shared context", "SharedContext/Shared context (second user)",
            "SharedContext/Modifier with stored properties",
            "BadgeLegacyPreviews/Legacy one", "BadgeLegacyPreviews/Legacy two",
            "BadgeLegacyPreviews/BadgeLegacyPreviews",
            "CardLegacyPreview/CardLegacyPreview",
        ]
        #expect(stories.map { "\($0.id.group)/\($0.id.name)" } == expected)
    }

    @Test func makesEveryStorysView() async throws {
        for story in stories {
            // Hosting and laying out the view runs SwiftUI's update graph, where Debug builds' view
            // replacement (DebugReplaceableView) crashed Xcode's own preview agent on legacy previews.
            layOut(try await story.makeView())
        }
    }

    @Test func readsLayoutTraits() throws {
        #expect(try story("Layouts", "Default layout").layout == .device)
        #expect(try story("Layouts", "Size that fits").layout == .sizeThatFits)
        #expect(try story("Layouts", "Fixed layout").layout == .fixed(width: 200, height: 80))
        #expect(try story("Card", "Card").layout == .device)
    }

    @Test func readsOrientationTraits() throws {
        #expect(try story("Layouts", "Landscape").orientation == .landscapeLeft)
        #expect(try story("Layouts", "Combined traits").orientation == .portrait)
        #expect(try story("Layouts", "Combined traits").layout == .sizeThatFits)
        #expect(try story("Layouts", "Default layout").orientation == nil)
    }

    @Test func recordsSourceLocations() throws {
        let story = try story("Layouts", "Fixed layout")
        #expect(story.fileID == "PreviewZoo/Layouts.swift")
        #expect(story.line == 29)
    }

    @Test func readsEachArgumentAsItsOwnStory() async throws {
        let short = try story("Arguments", "Badge arguments / NEW")
        let long = try story("Arguments", "Badge arguments / SOLD OUT")
        #expect(short.layout == .sizeThatFits)
        #expect(short.fileID == "PreviewZoo/Arguments.swift")
        #expect(short.line == long.line)
        let shortWidth = hostedSize(try await short.makeView()).width
        let longWidth = hostedSize(try await long.makeView()).width
        #expect(longWidth > shortWidth)
    }

    @Test func appliesSharedContextModifiers() async throws {
        let withLibrary = hostedSize(try await story("SharedContext", "Shared context").makeView())
        let withoutLibrary = hostedSize(AnyView(BookList()))
        #expect(withLibrary.height > withoutLibrary.height)
    }

    @Test func appliesModifiersWithStoredProperties() async throws {
        let size = hostedSize(
            try await story("SharedContext", "Modifier with stored properties").makeView())
        #expect(size.width == 300)
    }

    @Test func readsLegacyLayouts() throws {
        #expect(try story("BadgeLegacyPreviews", "Legacy one").layout == .device)
        #expect(try story("BadgeLegacyPreviews", "Legacy two").layout == .sizeThatFits)
        #expect(
            try story("BadgeLegacyPreviews", "BadgeLegacyPreviews").layout
                == .fixed(width: 120, height: 40))
        #expect(try story("CardLegacyPreview", "CardLegacyPreview").fileID == nil)
    }

    /// Hosts `view` at a fixed size and lays it out. Pixels are the renderer's concern.
    func layOut(_ view: AnyView) {
        #if os(macOS)
            let host = NSHostingView(rootView: view)
            host.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
            host.layoutSubtreeIfNeeded()
        #else
            let host = UIHostingController(rootView: view)
            host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
            host.view.layoutIfNeeded()
        #endif
    }

    /// The fitting size of `view` once hosted and laid out.
    func hostedSize(_ view: AnyView) -> CGSize {
        #if os(macOS)
            let host = NSHostingView(rootView: view)
            host.layoutSubtreeIfNeeded()
            return host.fittingSize
        #else
            let host = UIHostingController(rootView: view)
            host.view.layoutIfNeeded()
            return host.sizeThatFits(in: CGSize(width: 10_000, height: 10_000))
        #endif
    }
}
