import SwiftUI

// The legacy modifiers are deprecated as of the 27 SDKs. Marking the providers deprecated silences
// that inside them, and the fixture still covers code written before `#Preview`.

/// The legacy `PreviewProvider` format with a single preview.
@available(*, deprecated, message: "Legacy preview format fixture")
struct CardLegacyPreview: PreviewProvider {
    static var previews: some View {
        Card(title: "Legacy", subtitle: "PreviewProvider, one preview")
    }
}

/// The legacy format with several previews, each with its own name and layout.
@available(*, deprecated, message: "Legacy preview format fixture")
struct BadgeLegacyPreviews: PreviewProvider {
    static var previews: some View {
        Group {
            Badge("ONE").previewDisplayName("Legacy one")
            Badge("TWO").previewDisplayName("Legacy two").previewLayout(.sizeThatFits)
            Badge("THREE").previewLayout(.fixed(width: 120, height: 40))
        }
    }
}
