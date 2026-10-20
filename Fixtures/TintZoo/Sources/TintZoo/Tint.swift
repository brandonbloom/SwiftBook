import SwiftBook
import SwiftUI

/// Every story here is tinted with the asset catalog's AccentColor, as the app would be, and
/// one is left out of snapshot tests.
struct Snapshots: SwiftBookConfiguration {
    static var tint: Color? { Color("AccentColor", bundle: .module) }
    static var excluded: Set<String> { ["TintZoo/Tint/Viewer only"] }
}

#Preview("Tinted", traits: .fixedLayout(width: 240, height: 80)) {
    HStack(spacing: 16) {
        // A Mac draws prominent buttons without their tint in inactive windows, as render
        // windows are; the swatch shows the tint on every platform.
        Button("Tinted") {}
            .buttonStyle(.borderedProminent)
        RoundedRectangle(cornerRadius: 8)
            .fill(.tint)
            .frame(width: 48, height: 48)
    }
}

#Preview("Viewer only", traits: .sizeThatFitsLayout) {
    Text("Not snapshot-tested")
}
