import SwiftUI

/// A small badge, for exercising layout traits.
public struct Badge: View {
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.tint, in: .capsule)
            .foregroundStyle(.white)
    }
}

#Preview("Default layout", traits: .defaultLayout) {
    Badge("DEFAULT")
}

#Preview("Size that fits", traits: .sizeThatFitsLayout) {
    Badge("FITS")
}

#Preview("Fixed layout", traits: .fixedLayout(width: 200, height: 80)) {
    Badge("FIXED")
}

#Preview("Landscape", traits: .landscapeLeft) {
    Card(title: "Landscape", subtitle: "Orientation trait")
}

#Preview("Combined traits", traits: .sizeThatFitsLayout, .portrait) {
    Badge("COMBINED")
}
