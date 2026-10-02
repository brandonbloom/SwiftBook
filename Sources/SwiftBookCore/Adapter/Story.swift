import SwiftUI

/// A renderable story: one `#Preview`, one argument of a `#Preview(arguments:)`, or one child of a
/// `PreviewProvider`.
public struct Story: Identifiable, @unchecked Sendable {
    // Unchecked: `make` is main-actor isolated and only ever called there.

    public let id: StoryID
    /// The declaring file as `Module/File.swift`, for `#Preview`. Unknown for `PreviewProvider`.
    public let fileID: String?
    /// The 1-based line of the `#Preview`. Unknown for `PreviewProvider`.
    public let line: Int?
    public let layout: StoryLayout
    /// The orientation the preview asks for, or `nil` for the default.
    public let orientation: StoryOrientation?

    let make: @MainActor () async throws -> AnyView

    /// Builds the story's view, applying its preview modifiers.
    ///
    /// Throws ``AdapterError`` when the preview couldn't be read, and rethrows errors from
    /// `PreviewModifier.makeSharedContext()`.
    @MainActor public func makeView() async throws -> AnyView {
        try await make()
    }
}

/// How a story is sized, from its layout trait.
public enum StoryLayout: Hashable, Sendable {
    /// The full screen or window of the device.
    case device
    /// The view's ideal size.
    case sizeThatFits
    /// A fixed size, in points.
    case fixed(width: Double, height: Double)
}

/// An interface orientation requested by a preview.
public enum StoryOrientation: String, Hashable, Sendable {
    case portrait
    case portraitUpsideDown
    case landscapeLeft
    case landscapeRight
}

extension Story {
    /// Every story in the images loaded into this process, in ``DiscoveredPreview/all()`` order.
    ///
    /// A preview that the adapter can't read still yields a story, whose ``makeView()`` throws.
    /// Previews whose `makePreview()` throws `PreviewUnavailable` are left out, as in Xcode.
    @MainActor public static func all() -> [Story] {
        stories(from: DiscoveredPreview.all())
    }

    @MainActor static func stories(from previews: [DiscoveredPreview]) -> [Story] {
        let drafts = previews.flatMap { PreviewAdapter.drafts(for: $0) }
        let ids = StoryID.assign(drafts.map { ($0.module, $0.group, $0.displayName) })
        return zip(drafts, ids).map { draft, id in
            Story(
                id: id, fileID: draft.fileID, line: draft.line, layout: draft.layout,
                orientation: draft.orientation, make: draft.make)
        }
    }
}
