import SwiftUI
import Testing

@testable import SwiftBookCore

@MainActor @Suite struct PreviewAdapterTests {
    func drafts(_ preview: Preview) -> [PreviewAdapter.Draft] {
        PreviewAdapter.drafts(
            from: preview, module: "M", group: "File", fileID: "M/File.swift", line: 7,
            location: "M/File.swift:7")
    }

    @Test func readsAPreviewMadeDirectly() async throws {
        let drafts = drafts(Preview("Named", traits: .sizeThatFitsLayout) { Text("Hello") })
        #expect(drafts.count == 1)
        #expect(drafts.first?.displayName == "Named")
        #expect(drafts.first?.layout == .sizeThatFits)
        _ = try await drafts.first?.make()
    }

    @Test func failsLoudlyOnAnUnsupportedTrait() async throws {
        let drafts = drafts(Preview("Assistive", traits: .assistiveAccess) { Text("Hello") })
        // The story still exists, keeping its identity, but can't be rendered.
        #expect(drafts.count == 1)
        #expect(drafts.first?.displayName == "Assistive")
        do {
            _ = try await drafts.first?.make()
            Issue.record("expected an AdapterError")
        } catch let error as AdapterError {
            #expect(error.problem.hasPrefix("unsupported: preview trait"))
            #expect(error.location == "M/File.swift:7")
            #expect(
                error.description.contains("SwiftBook couldn't read the preview at M/File.swift:7"))
            #expect(error.description.contains("Environment: "))
        }
    }
}
