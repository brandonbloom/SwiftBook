import SwiftUI

#if DEBUG
    // Consumers commonly guard previews and fixtures out of release builds.
    #Preview("Debug only") {
        Card(title: "Debug", subtitle: "Inside #if DEBUG")
    }
#endif

// Characters that aren't safe in file names.
#Preview("Slash / colon: and émoji 🌙") {
    Badge("ODD NAME")
}

// Two previews in one file with the same name.
#Preview("Duplicate") {
    Badge("FIRST")
}

#Preview("Duplicate") {
    Badge("SECOND")
}
