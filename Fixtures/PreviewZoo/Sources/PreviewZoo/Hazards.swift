import SwiftUI

// Content that tends to render wrong outside a real window: platform-backed controls, materials,
// blur, scrolling, and locale- and time-dependent text.

#Preview("List") {
    List {
        Section("Fruits") {
            ForEach(["Apple", "Banana", "Cherry"], id: \.self) { Label($0, systemImage: "leaf") }
        }
        Section("Settings") {
            Toggle("Wi-Fi", isOn: .constant(true))
            Text("Footer row")
        }
    }
}

#Preview("Text fields") {
    @Previewable @State var name = "Brandon"
    @Previewable @State var empty = ""
    VStack {
        TextField("Name", text: $name)
        TextField("Empty placeholder", text: $empty)
    }
    .padding()
}

#Preview("Material and blur") {
    ZStack {
        LinearGradient(
            colors: [.orange, .pink, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
        VStack(spacing: 24) {
            Text("Material panel")
                .padding()
                .background(.regularMaterial, in: .rect(cornerRadius: 8))
            Circle().fill(.yellow).frame(width: 40, height: 40).blur(radius: 4)
        }
    }
}

#Preview("Scroll view") {
    ScrollView {
        LazyVStack {
            ForEach(0..<40) { Text("Row \($0)").frame(maxWidth: .infinity).padding(8) }
        }
    }
}

#Preview("Dates") {
    let date = Date(timeIntervalSince1970: 1_790_000_000)
    VStack(alignment: .leading) {
        Text(date, style: .date)
        Text(date, style: .time)
        Text(date.formatted(.dateTime.year().month().day().hour().minute()))
    }
    .padding()
}

// Foundation formatting reads the process's time zone and locale, not SwiftUI's environment.
#Preview("Foundation-formatted date") {
    Text(Date(timeIntervalSince1970: 1_790_000_000).formatted(.dateTime.hour().minute()))
        .padding()
}

// Indeterminate progress animates forever, and must still render the same frame every time.
#Preview("Progress", traits: .sizeThatFitsLayout) {
    VStack(spacing: 12) {
        ProgressView()
        ProgressView().controlSize(.small)
        ScrollView {
            HStack {
                ProgressView().controlSize(.small)
                Text("Checking…")
            }
        }
        .frame(height: 40)
    }
    .padding()
}

// Liquid Glass over content: a tab bar with a selected tab's lens and a glass toolbar button.
// The render server draws these in a few states from run to run (see
// docs/research/liquid-glass-noise.md), so this keeps glass comparison under test.
#Preview("Liquid Glass") {
    TabView {
        Tab("Spending", systemImage: "chart.pie") {
            NavigationStack {
                List(0..<30) { row in
                    HStack {
                        Text("Row \(row)")
                        Spacer()
                        Text("$\(row * 1234)").monospacedDigit()
                    }
                }
                .navigationTitle("Spending")
                .toolbar {
                    ToolbarItem { Button("Add", systemImage: "plus") {} }
                }
            }
        }
        Tab("Accounts", systemImage: "building.columns") { Text("Accounts") }
        Tab(role: .search) { Text("Search") }
    }
}
