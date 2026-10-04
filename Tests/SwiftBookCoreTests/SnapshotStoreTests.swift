import CoreGraphics
import Foundation
import Testing

@testable import SwiftBookCore

@Suite struct SnapshotStoreTests {
    let story = StoryID(module: "Zoo", group: "Card", name: "Card (dark)")
    let directory = FileManager.default.temporaryDirectory.appending(
        path: "SnapshotStoreTests-\(UUID())")
    var store: SnapshotStore { SnapshotStore(root: directory.appending(path: "Snapshots")) }

    func snapshot(gray: UInt8, environment: RenderEnvironment = RenderEnvironment()) -> Snapshot {
        let pixels = [UInt8](repeating: 0, count: 4 * 4 * 4).enumerated().map {
            $0.offset % 4 == 3 ? 255 : gray
        }
        let metadata = SnapshotMetadata(
            story: story.description, device: "mac", platform: "macOS", osVersion: "27.0.0",
            scale: 2,
            appearance: environment.appearance.rawValue, locale: environment.localeIdentifier,
            timeZone: environment.timeZoneIdentifier, dynamicTypeSize: "large",
            layoutDirection: "leftToRight",
            swiftBookVersion: SwiftBookInfo.version)
        return Snapshot(
            story: story, device: .mac, environment: environment,
            image: Bitmap(width: 4, height: 4, pixels: pixels).image()!, metadata: metadata)
    }

    // MARK: Layout

    @Test func laysOutReferencesByModuleGroupAndStory() {
        var dark = RenderEnvironment()
        dark.appearance = .dark
        let url = store.url(for: story, device: .mac, environment: dark)
        #expect(url.path.hasSuffix("Snapshots/Zoo/Card/Card (dark)/mac.dark.png"))
    }

    @Test func namesVariantsByNonDefaultDimensions() {
        var environment = RenderEnvironment()
        #expect(
            SnapshotStore.variantName(device: .iphone, environment: environment) == "iphone.light")
        environment.dynamicTypeSize = .xxxLarge
        environment.layoutDirection = .rightToLeft
        environment.localeIdentifier = "ar_EG"
        #expect(
            SnapshotStore.variantName(device: .iphone, environment: environment)
                == "iphone.light.xxxLarge.rtl.ar_EG")
        // Pinned settings that aren't dimensions stay out of the name.
        environment = RenderEnvironment()
        environment.scale = 3
        environment.timeZoneIdentifier = "Asia/Tokyo"
        #expect(SnapshotStore.variantName(device: .mac, environment: environment) == "mac.light")
    }

    @Test(arguments: [
        ("Card", "Card"),
        ("Slash / colon: and émoji 🌙", "Slash _ colon_ and émoji 🌙"),
        ("Badge arguments / NEW", "Badge arguments _ NEW"),
        ("trailing. ", "trailing"),
        (".hidden", "_hidden"),
        ("", "_"),
        ("tab\there", "tab_here"),
    ])
    func sanitizesNamesIntoPathComponents(name: String, fileName: String) {
        #expect(SnapshotStore.fileName(name) == fileName)
    }

    @Test func findsTheEnclosingPackage() throws {
        let store = try SnapshotStore.forProject(containing: #filePath)
        let packageRoot = URL(filePath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        #expect(
            store.root.standardizedFileURL.path
                == packageRoot.appending(path: "Snapshots").standardizedFileURL.path)
    }

    // MARK: Record modes

    @Test func parsesTheRecordModeFromTheEnvironment() throws {
        #expect(try RecordMode.fromEnvironment([:]) == .missing)
        #expect(try RecordMode.fromEnvironment(["SWIFTBOOK_RECORD": "never"]) == .never)
        #expect(throws: StorageError.self) {
            try RecordMode.fromEnvironment(["SWIFTBOOK_RECORD": "yes"])
        }
    }

    @Test func recordsMissingReferencesThenMatchesThem() throws {
        guard
            case .recorded(let url, previous: nil, replaced: nil) = try store.verify(
                snapshot(gray: 100), mode: .missing)
        else {
            Issue.record("expected a recording")
            return
        }
        #expect(FileManager.default.fileExists(atPath: url.path))
        guard case .matched(let diff) = try store.verify(snapshot(gray: 100), mode: .missing) else {
            Issue.record("expected a match")
            return
        }
        #expect(diff.isIdentical)
    }

    @Test func reportsMismatchesWithTheReferenceMetadata() throws {
        _ = try store.verify(snapshot(gray: 100), mode: .missing)
        guard
            case .mismatched(let diff, _, let metadata) = try store.verify(
                snapshot(gray: 200), mode: .missing)
        else {
            Issue.record("expected a mismatch")
            return
        }
        #expect(diff.changedPixels == 16)
        #expect(metadata?.osVersion == "27.0.0")
    }

    @Test func rerecordsChangedReferencesInChangedMode() throws {
        _ = try store.verify(snapshot(gray: 100), mode: .missing)
        guard
            case .recorded(_, let previous, let replaced) = try store.verify(
                snapshot(gray: 200), mode: .changed)
        else {
            Issue.record("expected a recording")
            return
        }
        #expect(previous?.changedPixels == 16)
        #expect(replaced == (try snapshot(gray: 100).pngData()))
        guard case .matched = try store.verify(snapshot(gray: 200), mode: .never) else {
            Issue.record("expected the new reference to match")
            return
        }
    }

    @Test func neverRecordsInNeverMode() throws {
        guard case .missing(let url) = try store.verify(snapshot(gray: 100), mode: .never) else {
            Issue.record("expected a missing reference")
            return
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func rerecordsEverythingThatDiffersInAllMode() throws {
        _ = try store.verify(snapshot(gray: 100), mode: .missing)
        // Even a change within tolerance is recorded.
        guard
            case .recorded(_, let previous, let replaced) = try store.verify(
                snapshot(gray: 101), mode: .all)
        else {
            Issue.record("expected a recording")
            return
        }
        #expect(previous?.matches == true)
        #expect(previous?.isIdentical == false)
        #expect(replaced == (try snapshot(gray: 100).pngData()))
    }

    @Test func leavesIdenticalReferencesAloneInAllMode() throws {
        _ = try store.verify(snapshot(gray: 100), mode: .missing)
        guard case .matched(let diff) = try store.verify(snapshot(gray: 100), mode: .all) else {
            Issue.record("expected a match")
            return
        }
        #expect(diff.isIdentical)
    }

    @Test func explainsGitLFSPointers() throws {
        let url = store.url(for: story, device: .mac, environment: RenderEnvironment())
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("version https://git-lfs.github.com/spec/v1\noid sha256:abc\nsize 12\n".utf8)
            .write(to: url)
        do {
            _ = try store.verify(snapshot(gray: 100), mode: .missing)
            Issue.record("expected an error")
        } catch let error as StorageError {
            #expect(error.description.contains("Git LFS pointer"))
        }
    }
}
