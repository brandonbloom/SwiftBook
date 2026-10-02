import SwiftUI

/// A plain SwiftUI view: text, an SF Symbol, and a gradient.
public struct Card: View {
    let title: String
    let subtitle: String

    public init(title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            Label("Starred", systemImage: "star.fill").font(.caption)
        }
        .padding()
        .frame(maxWidth: 320, alignment: .leading)
        .background(
            LinearGradient(
                colors: [.blue.opacity(0.3), .purple.opacity(0.3)], startPoint: .top,
                endPoint: .bottom),
            in: .rect(cornerRadius: 12))
    }
}

// Unnamed: identity falls back to the preview's order within the file.
#Preview {
    Card(title: "Unnamed", subtitle: "First unnamed preview in the file")
}

#Preview {
    Card(title: "Unnamed", subtitle: "Second unnamed preview in the file")
}

#Preview("Card") {
    Card(title: "Hello", subtitle: "A named preview")
}

// Statements before the view, as consumers write when setting up fixtures.
#Preview("Card (statements)") {
    let title = ["Hello", "World"].joined(separator: ", ")
    Card(title: title, subtitle: "Body with a let statement")
}
