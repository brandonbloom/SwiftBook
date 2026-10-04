// Snapshot testing of discovered stories under Swift Testing.

import Foundation
@_exported import SwiftBookCore
import Testing

/// Snapshot-tests every story in the test target: one Swift Testing test case per story, which
/// renders each variant and compares it with the reference in the project's `Snapshots/`.
///
/// ```swift
/// import SwiftBookTesting
/// import Testing
///
/// #SwiftBookTests
/// ```
///
/// The file must import Testing itself: the expansion uses its macros, which modules can't
/// re-export.
///
/// - Parameters:
///   - variants: The variants recorded for every story. Light and dark by default.
///   - tolerance: What counts as a change.
///   - excluding: Stories to leave out, as `Module/Group/Name`.
@freestanding(declaration, names: named(SwiftBookSnapshots))
public macro SwiftBookTests(
    variants: Variants = .lightAndDark, tolerance: ImageDiff.Tolerance = ImageDiff.Tolerance(),
    excluding: Set<String> = []
) = #externalMacro(module: "SwiftBookMacros", type: "SwiftBookTestsMacro")

/// The rendering environments recorded for each story.
public struct Variants: Sendable {
    public let environments: [RenderEnvironment]

    public init(_ environments: [RenderEnvironment]) {
        self.environments = environments
    }

    /// One variant per appearance, otherwise like `base`.
    public init(
        appearances: [RenderEnvironment.Appearance], base: RenderEnvironment = RenderEnvironment()
    ) {
        self.init(
            appearances.map { appearance in
                var environment = base
                environment.appearance = appearance
                return environment
            })
    }

    public static let lightAndDark = Variants(appearances: [.light, .dark])
}

/// A story as a Swift Testing argument.
public struct TestStory: Sendable, Identifiable, CustomTestStringConvertible {
    public let story: Story
    public var id: String { story.id.description }
    public var testDescription: String { story.id.description }
}

/// The functions `#SwiftBookTests` expands to call.
public enum SwiftBook {
    /// Whether snapshots can be taken in this process. iOS and tvOS snapshots need a host app, so
    /// they run through `swiftbook test` instead.
    public static var canSnapshot: Bool {
        #if os(macOS)
            true
        #else
            false
        #endif
    }

    /// Every story in this process, except `excluded` ones (as `Module/Group/Name`).
    public static func stories(excluding excluded: Set<String> = []) async -> [TestStory] {
        await MainActor.run {
            Story.all().filter { !excluded.contains($0.id.description) }.map(TestStory.init)
        }
    }

    /// Renders each variant of `story` and checks it against its reference, recording an issue
    /// for every variant that fails.
    ///
    /// - Parameters:
    ///   - filePath: A file in the project, which locates its `Snapshots/` directory.
    ///   - store: Overrides where references live.
    ///   - mode: Overrides `SWIFTBOOK_RECORD`.
    @MainActor public static func verify(
        _ story: TestStory, filePath: String, variants: Variants = .lightAndDark,
        tolerance: ImageDiff.Tolerance = ImageDiff.Tolerance(), excluding _: Set<String> = [],
        store: SnapshotStore? = nil, mode: RecordMode? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        #if os(macOS)
            let store = try store ?? SnapshotStore.forProject(containing: filePath)
            let mode = try mode ?? RecordMode.fromEnvironment()
            for environment in variants.environments {
                let snapshot = try await MacRenderer.render(story.story, in: environment)
                let verification = try store.verify(snapshot, mode: mode, tolerance: tolerance)
                try report(
                    verification, of: snapshot, mode: mode, store: store,
                    sourceLocation: sourceLocation)
            }
        #else
            Issue.record(
                "iOS and tvOS snapshots run through `swiftbook test`, which renders in a host app",
                sourceLocation: sourceLocation)
        #endif
    }

    @MainActor private static func report(
        _ verification: Verification, of snapshot: Snapshot, mode: RecordMode, store: SnapshotStore,
        sourceLocation: SourceLocation
    ) throws {
        let variant = SnapshotStore.variantName(
            device: snapshot.device, environment: snapshot.environment)
        let subject = "\(snapshot.story) (\(variant))"
        let message: String
        let kind: ReviewEntry.Kind
        var images: [ReviewEntry.Image] = []
        var severity = Issue.Severity.error
        let artifacts: Artifacts
        switch verification {
        case .matched:
            return
        case .recorded(let url, let previous, let replaced):
            artifacts = try Artifacts(for: url, store: store, kind: "recorded")
            if let replaced {
                images.append(try artifacts.write(replaced, as: "previous"))
            }
            images.append(try artifacts.write(Data(contentsOf: url), as: "new"))
            let diffImage = try previous?.pngData().map { try artifacts.write($0, as: "diff") }
            if let diffImage { images.append(diffImage) }
            message = recordedMessage(
                subject: subject, reference: relative(url, to: store), previous: previous,
                diffImage: diffImage.map { URL(filePath: $0.path) })
            kind = previous == nil ? .new : .changed
            // Recording on request passes with a warning, so the run lists what to review.
            // Recording because nothing existed fails, so a new reference gets reviewed before
            // it's committed.
            if mode != .missing || previous != nil { severity = .warning }
        case .missing(let url):
            artifacts = try Artifacts(for: url, store: store, kind: "failures")
            message = """
                No reference for \(subject) at \(relative(url, to: store)). Record one with \
                \(RecordMode.environmentVariable)=missing.
                """
            kind = .missing
        case .mismatched(let diff, let url, let referenceMetadata):
            artifacts = try Artifacts(for: url, store: store, kind: "failures")
            images.append(try artifacts.write(Data(contentsOf: url), as: "reference"))
            images.append(try artifacts.write(snapshot.pngData(), as: "actual"))
            if let diffPNG = try diff.pngData() {
                images.append(try artifacts.write(diffPNG, as: "diff"))
            }
            message = mismatchMessage(
                subject: subject, diff: diff, reference: relative(url, to: store),
                referenceMetadata: referenceMetadata, actualMetadata: snapshot.metadata,
                artifacts: artifacts.directory)
            kind = .failed
        }
        for image in images {
            if let data = try? Data(contentsOf: URL(filePath: image.path)) {
                Attachment.record(data, named: "\(variant).\(image.role).png")
            }
        }
        let page = try artifacts.add(
            ReviewEntry(
                story: snapshot.story.description, variant: variant, kind: kind, message: message,
                images: images))
        Issue.record(
            Comment(rawValue: message + "\nReview page: \(page.path)"), severity: severity,
            sourceLocation: sourceLocation)
    }

    static func mismatchMessage(
        subject: String, diff: ImageDiff, reference: String, referenceMetadata: SnapshotMetadata?,
        actualMetadata: SnapshotMetadata, artifacts: URL
    ) -> String {
        var lines = ["\(subject) doesn't match \(reference).", change(diff)]
        if let referenceMetadata, referenceMetadata != actualMetadata {
            let changes = environmentChanges(from: referenceMetadata, to: actualMetadata)
            if !changes.isEmpty {
                lines.append(
                    "The rendering environment also changed: \(changes.joined(separator: "; ")).")
            }
        }
        lines.append("Actual and diff images: \(artifacts.path)")
        lines.append("To accept the change: \(RecordMode.environmentVariable)=changed swift test")
        return lines.joined(separator: "\n")
    }

    static func recordedMessage(
        subject: String, reference: String, previous: ImageDiff?, diffImage: URL?
    ) -> String {
        guard let previous else {
            return
                "Recorded a new reference for \(subject) at \(reference). Review it, then commit it."
        }
        var lines = ["Re-recorded \(subject) at \(reference)."]
        lines.append(
            previous.matches
                ? "It's within tolerance of the reference it replaced." : change(previous))
        if let diffImage { lines.append("Diff image: \(diffImage.path)") }
        lines.append("Review it, then commit it.")
        return lines.joined(separator: "\n")
    }

    /// How an image differs from its reference, as a sentence.
    static func change(_ diff: ImageDiff) -> String {
        guard diff.sizesMatch else {
            return
                "Size changed from \(Int(diff.expectedSize.width))×\(Int(diff.expectedSize.height)) "
                + "to \(Int(diff.actualSize.width))×\(Int(diff.actualSize.height)) pixels."
        }
        let percent = (diff.changedPixelRatio * 100).formatted(
            .number.precision(.fractionLength(0...2)))
        var line =
            "\(diff.changedPixels) pixels changed (\(percent)%), max ΔE \(Int(diff.maxDeltaE.rounded()))"
        if let bounds = diff.changedBounds {
            line +=
                ", within \(Int(bounds.width))×\(Int(bounds.height)) at (\(Int(bounds.minX)), \(Int(bounds.minY)))"
        }
        return line + "."
    }

    /// The rendering-environment fields that differ, such as an OS update.
    static func environmentChanges(from reference: SnapshotMetadata, to actual: SnapshotMetadata)
        -> [String]
    {
        var changes: [String] = []
        func compare(_ name: String, _ keyPath: KeyPath<SnapshotMetadata, String>) {
            if reference[keyPath: keyPath] != actual[keyPath: keyPath] {
                changes.append(
                    "\(name) \(reference[keyPath: keyPath]) → \(actual[keyPath: keyPath])")
            }
        }
        compare("OS", \.osVersion)
        compare("SwiftBook", \.swiftBookVersion)
        compare("locale", \.locale)
        compare("time zone", \.timeZone)
        if reference.capture != actual.capture {
            changes.append(
                "capture \(reference.capture ?? "emulated") → \(actual.capture ?? "emulated")")
        }
        if reference.scale != actual.scale {
            changes.append("scale \(reference.scale) → \(actual.scale)")
        }
        return changes
    }

    private static func relative(_ url: URL, to store: SnapshotStore) -> String {
        let project = store.root.deletingLastPathComponent().path
        return url.path.hasPrefix(project)
            ? String(url.path.dropFirst(project.count + 1)) : url.path
    }
}

/// Images and review entries for people to look at, in `$SWIFTBOOK_ARTIFACTS` or else the
/// project's `.build/swiftbook`.
///
/// Each kind ("failures", "recorded") gets a directory mirroring `Snapshots/`. The first artifact a
/// process writes clears the previous run's, so the review page shows only the latest run.
@MainActor struct Artifacts {
    /// The artifacts root.
    let base: URL
    /// The path for this reference's artifacts, without an extension, such as
    /// `failures/Module/Group/Story/mac.light`.
    let stem: URL

    var directory: URL { stem.deletingLastPathComponent() }

    /// Artifact roots cleared by this process.
    private static var cleared: Set<URL> = []

    init(for reference: URL, store: SnapshotStore, kind: String) throws {
        base =
            ProcessInfo.processInfo.environment["SWIFTBOOK_ARTIFACTS"].map { URL(filePath: $0) }
            ?? store.root.deletingLastPathComponent().appending(path: ".build/swiftbook")
        if Self.cleared.insert(base).inserted {
            for previous in Self.kinds + ["review"] {
                try? FileManager.default.removeItem(at: base.appending(path: previous))
            }
        }
        stem = base.appending(path: kind)
            .appending(path: String(reference.path.dropFirst(store.root.path.count)))
            .deletingPathExtension()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
    }

    private static let kinds = ["failures", "recorded"]

    /// Writes `png` beside the others, named for its `role`.
    func write(_ png: Data, as role: String) throws -> ReviewEntry.Image {
        let url = stem.appendingPathExtension("\(role).png")
        try png.write(to: url)
        return ReviewEntry.Image(role: role, path: url.path)
    }

    /// Saves `entry`, rewrites the review page from every saved entry, and returns the page.
    func add(_ entry: ReviewEntry) throws -> URL {
        try JSONEncoder().encode(entry).write(to: stem.appendingPathExtension("json"))
        var entries: [ReviewEntry] = []
        for kind in Self.kinds {
            let enumerator = FileManager.default.enumerator(
                at: base.appending(path: kind), includingPropertiesForKeys: nil)
            while let url = enumerator?.nextObject() as? URL {
                guard url.pathExtension == "json", let data = try? Data(contentsOf: url),
                    let entry = try? JSONDecoder().decode(ReviewEntry.self, from: data)
                else { continue }
                entries.append(entry)
            }
        }
        let page = base.appending(path: "review/index.html")
        try ReviewPage.write(entries, to: page)
        return page
    }
}
