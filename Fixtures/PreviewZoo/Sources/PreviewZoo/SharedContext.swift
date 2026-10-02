import SwiftUI

/// Data that's expensive to build, shared across previews through a `PreviewModifier`.
public struct Library: Sendable {
    public let books: [String]
}

struct SampleLibrary: PreviewModifier {
    static func makeSharedContext() async throws -> Library {
        Library(books: ["Dune", "Neuromancer", "Hyperion"])
    }

    func body(content: Content, context: Library) -> some View {
        content.environment(\.bookTitles, context.books)
    }
}

extension EnvironmentValues {
    @Entry var bookTitles: [String] = []
}

extension PreviewTrait where T == Preview.ViewTraits {
    @MainActor static var sampleLibrary: Self = .modifier(SampleLibrary())
}

/// Lists the books provided by the environment.
public struct BookList: View {
    @Environment(\.bookTitles) private var titles

    public init() {}

    public var body: some View {
        VStack(alignment: .leading) {
            ForEach(titles, id: \.self) { Text($0) }
        }
        .padding()
    }
}

#Preview("Shared context", traits: .sampleLibrary) {
    BookList()
}

#Preview("Shared context (second user)", traits: .sampleLibrary, .sizeThatFitsLayout) {
    BookList()
}

/// A modifier with stored properties, so applying it depends on their layout being read correctly.
struct FixedWidth: PreviewModifier {
    let width: CGFloat
    let label: String

    func body(content: Content, context: Void) -> some View {
        content.frame(width: width).accessibilityLabel(label)
    }
}

#Preview(
    "Modifier with stored properties", traits: .modifier(FixedWidth(width: 300, label: "wide")),
    .sizeThatFitsLayout
) {
    Badge("WIDE")
}
