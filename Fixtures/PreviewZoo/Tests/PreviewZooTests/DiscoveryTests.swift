import Foundation
import PreviewZoo
import SwiftBookCore
import Testing

@Suite struct DiscoveryTests {
    let previews = DiscoveredPreview.all().filter { $0.module == "PreviewZoo" }

    @Test func findsEveryPreviewMacroByFile() {
        var counts: [String: Int] = [:]
        for preview in previews {
            if let fileID = preview.fileID { counts[fileID, default: 0] += 1 }
        }
        var expected = [
            "PreviewZoo/Arguments.swift": 1,
            "PreviewZoo/Card.swift": 4,
            "PreviewZoo/Chrome.swift": 2,
            "PreviewZoo/EdgeCases.swift": 4,
            "PreviewZoo/Hazards.swift": 7,
            "PreviewZoo/Layouts.swift": 5,
            "PreviewZoo/Previewable.swift": 1,
            "PreviewZoo/SharedContext.swift": 3,
        ]
        #if os(macOS)
            expected["PreviewZoo/PlatformViews.swift"] = 3  // NSView, NSViewController, macOS only
        #else
            expected["PreviewZoo/PlatformViews.swift"] = 2  // UIView, UIViewController
        #endif
        #expect(counts == expected)
    }

    @Test func findsPreviewProviders() {
        let names = previews.compactMap(\.providerName)
        #expect(names == ["BadgeLegacyPreviews", "CardLegacyPreview"])
    }

    @Test func ordersBySourceLocationThenProviderName() {
        let cardLines = previews.filter { $0.fileID == "PreviewZoo/Card.swift" }.compactMap(\.line)
        #expect(cardLines == cardLines.sorted())
        #expect(cardLines.count == 4)
        // Providers, which have no file, come after every `#Preview`.
        let firstProvider = previews.firstIndex { $0.fileID == nil }
        #expect(firstProvider == previews.count - 2)
    }

    @Test func findsOnlyTheZoosPreviews() {
        // SwiftUI and other system frameworks are skipped; only the zoo declares previews here.
        #expect(Set(DiscoveredPreview.all().map(\.module)) == ["PreviewZoo"])
    }

    @Test func isFast() {
        let clock = ContinuousClock()
        let elapsed = clock.measure { _ = DiscoveredPreview.all() }
        #expect(elapsed < .milliseconds(100))
    }
}
