import SwiftUI

/// The first screen of the app: a symbol over a gradient, and a Liquid Glass button.
public struct Welcome: View {
    public init() {}

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [.orange, .pink, .purple], startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "airplane.departure")
                    .font(.system(size: 72))
                Text("Wander").font(.largeTitle.bold())
                Text("Every trip, planned in one place.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                Spacer()
                Button("Get Started") {}
                    .buttonStyle(.glassProminent)
                    .tint(.indigo)
                    .controlSize(.large)
            }
            .foregroundStyle(.white)
            .padding(32)
        }
    }
}

#Preview("Welcome") {
    Welcome()
}
