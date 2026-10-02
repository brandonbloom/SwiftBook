import SwiftUI

/// Parameterized previews: one preview declaration, one rendering per argument.
#Preview("Badge arguments", traits: .sizeThatFitsLayout, arguments: ["NEW", "SALE", "SOLD OUT"]) {
    text in
    Badge(text)
}
