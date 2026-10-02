import SwiftUI

/// A counter whose state lives in the preview through `@Previewable`.
public struct Counter: View {
    @Binding var count: Int

    public init(count: Binding<Int>) {
        _count = count
    }

    public var body: some View {
        HStack {
            Text("Count: \(count)")
            Button("Increment") { count += 1 }
        }
        .padding()
    }
}

#Preview("Previewable state") {
    @Previewable @State var count = 3
    Counter(count: $count)
}
