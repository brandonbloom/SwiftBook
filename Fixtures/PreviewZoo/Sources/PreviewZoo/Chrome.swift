import SwiftUI

// Window chrome that AppKit draws with system materials and the accent color, which an offscreen
// capture can miss.

/// A sidebar with a selected row and an accent-colored avatar, both drawn with vibrancy.
struct SidebarWindow: View {
    @State private var selection: String? = "Banana"

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Fruits") {
                    ForEach(["Apple", "Banana", "Cherry"], id: \.self) { fruit in
                        Label(fruit, systemImage: "leaf")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    AvatarMenu()
                    AvatarMenu(fill: .purple)
                    VStack(alignment: .leading) {
                        Text("Brandon")
                        Text("Signed in").foregroundStyle(.secondary)
                    }
                }
            }
        } detail: {
            Text(selection ?? "Nothing selected")
        }
    }
}

/// A circular avatar, filled with the accent color by default, as a menu label.
struct AvatarMenu: View {
    var fill = Color.accentColor

    var body: some View {
        Menu {
            Button("Sign Out") {}
        } label: {
            Text("B")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(fill))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .padding()
    }
}

#Preview("Sidebar selection", traits: .fixedLayout(width: 600, height: 300)) {
    SidebarWindow()
}

#Preview("Accent avatar", traits: .sizeThatFitsLayout) {
    AvatarMenu()
}
