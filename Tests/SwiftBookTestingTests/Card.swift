import SwiftUI

// A story for VerifyTests: text and a gradient, which differ between light and dark.
#Preview("Card", traits: .sizeThatFitsLayout) {
    VStack(alignment: .leading, spacing: 6) {
        Text("Hello").font(.headline)
        Text("A named preview").font(.subheadline).foregroundStyle(.secondary)
    }
    .padding()
    .frame(width: 240, alignment: .leading)
    .background(
        LinearGradient(
            colors: [.blue.opacity(0.3), .purple.opacity(0.3)], startPoint: .top, endPoint: .bottom),
        in: .rect(cornerRadius: 12))
}
