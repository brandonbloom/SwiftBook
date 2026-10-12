import Foundation
import SwiftUI

#Preview("Fine") {
    Text("Fine").padding()
}

#Preview("Crashes") {
    let _: Int = { fatalError("this preview crashes") }()
    Text("Unreachable")
}

#Preview("Hangs") {
    // Blocks the renderer's main thread, as a deadlock would.
    let _: Void = { while true { usleep(100_000) } }()
    Text("Unreachable")
}

#Preview("Slow") {
    let _: Void = { Thread.sleep(forTimeInterval: 1) }()
    Text("Slow").padding()
}

// Renders differently each launch, as a preview reading random or live data would.
#Preview("Flaky") {
    Text("Roll: \(Int.random(in: 1...3))").padding()
}
