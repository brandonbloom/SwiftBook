import Foundation
import Synchronization

/// What a person should hear about a verification: a failure or a warning, with images to look at
/// and an entry on the review page.
public struct SnapshotReport: Sendable {
    public enum Severity: Sendable {
        /// The snapshot fails.
        case failure
        /// The snapshot passes, but someone should review what changed.
        case warning
    }

    /// The commands a message suggests, which depend on the tool that ran.
    public struct Hints: Sendable {
        /// How to accept a changed snapshot.
        public var accept: String
        /// How to record a missing reference.
        public var record: String

        public init(accept: String, record: String) {
            self.accept = accept
            self.record = record
        }

        /// For `swift test`.
        public static let swiftTest = Hints(
            accept: "\(RecordMode.environmentVariable)=changed swift test",
            record: "\(RecordMode.environmentVariable)=missing")
    }

    /// The story and variant, as `Module/Group/Name (mac.light)`.
    public let subject: String
    /// The variant's file name, such as `mac.light`.
    public let variant: String
    public let severity: Severity
    /// What happened to the reference.
    public let kind: ReviewEntry.Kind
    /// What happened and what to do, ending with the review page's path.
    public let message: String
    /// Images written for review: reference, actual, diff, and so on.
    public let images: [ReviewEntry.Image]

    /// Reports `verification`, writing its images and review entry, or returns `nil` if the
    /// snapshot matched.
    public init?(
        _ verification: Verification, of snapshot: Snapshot, mode: RecordMode,
        store: SnapshotStore, hints: Hints
    ) throws {
        variant = SnapshotStore.variantName(
            device: snapshot.device, environment: snapshot.environment)
        subject = "\(snapshot.story) (\(variant))"
        let message: String
        let kind: ReviewEntry.Kind
        var images: [ReviewEntry.Image] = []
        var region: ImageDiff.PixelRect?
        var severity = Severity.failure
        let artifacts: Artifacts
        switch verification {
        case .matched:
            return nil
        case .recorded(let url, let previous, let replaced):
            artifacts = try Artifacts(for: url, store: store, kind: "recorded")
            if let replaced {
                images.append(try artifacts.write(replaced, as: "previous"))
            }
            images.append(try artifacts.write(Data(contentsOf: url), as: "new"))
            let diffImage = try previous?.pngData().map { try artifacts.write($0, as: "diff") }
            if let diffImage { images.append(diffImage) }
            message = Self.recordedMessage(
                subject: subject, reference: Self.relative(url, to: store), previous: previous,
                diffImage: diffImage.map { URL(filePath: $0.path) })
            kind = previous == nil ? .new : .changed
            region = previous?.changedRegion
            // Recording on request passes with a warning, so the run lists what to review.
            // Recording because nothing existed fails, so a new reference gets reviewed before
            // it's committed.
            if mode != .missing || previous != nil { severity = .warning }
        case .missing(let url):
            artifacts = try Artifacts(for: url, store: store, kind: "failures")
            message =
                "No reference for \(subject) at \(Self.relative(url, to: store)). Record one with \(hints.record)."
            kind = .missing
        case .mismatched(let diff, let url, let referenceMetadata):
            artifacts = try Artifacts(for: url, store: store, kind: "failures")
            images.append(try artifacts.write(Data(contentsOf: url), as: "reference"))
            images.append(try artifacts.write(snapshot.pngData(), as: "actual"))
            if let diffPNG = try diff.pngData() {
                images.append(try artifacts.write(diffPNG, as: "diff"))
            }
            message = Self.mismatchMessage(
                subject: subject, diff: diff, reference: Self.relative(url, to: store),
                referenceMetadata: referenceMetadata, actualMetadata: snapshot.metadata,
                artifacts: artifacts.directory, hints: hints)
            kind = .failed
            region = diff.changedRegion
        }
        let page = try artifacts.add(
            ReviewEntry(
                story: snapshot.story.description, variant: variant, kind: kind, message: message,
                images: images, region: region))
        self.severity = severity
        self.kind = kind
        self.images = images
        self.message = message + "\nReview page: \(page.path)"
    }

    static func mismatchMessage(
        subject: String, diff: ImageDiff, reference: String, referenceMetadata: SnapshotMetadata?,
        actualMetadata: SnapshotMetadata, artifacts: URL, hints: Hints
    ) -> String {
        var lines = ["\(subject) doesn't match \(reference).", change(diff)]
        if diff.glassNoisePixels > 0 {
            lines.append(
                "\(diff.glassNoisePixels) more pixels differ inside Liquid Glass, but only as glass's run-to-run noise; they don't count."
            )
        }
        if let referenceMetadata, referenceMetadata != actualMetadata {
            let changes = environmentChanges(from: referenceMetadata, to: actualMetadata)
            if !changes.isEmpty {
                lines.append(
                    "The rendering environment also changed: \(changes.joined(separator: "; ")).")
            }
        }
        lines.append("Actual and diff images: \(artifacts.path)")
        lines.append("To accept the change: \(hints.accept)")
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
        if reference.tint != actual.tint {
            changes.append("tint \(reference.tint ?? "none") → \(actual.tint ?? "none")")
        }
        return changes
    }

    static func relative(_ url: URL, to store: SnapshotStore) -> String {
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
struct Artifacts {
    /// The artifacts root.
    let base: URL
    /// The path for this reference's artifacts, without an extension, such as
    /// `failures/Module/Group/Story/mac.light`.
    let stem: URL

    var directory: URL { stem.deletingLastPathComponent() }

    /// Artifact roots cleared by this process.
    private static let cleared = Mutex<Set<URL>>([])

    init(for reference: URL, store: SnapshotStore, kind: String) throws {
        let base =
            ProcessInfo.processInfo.environment["SWIFTBOOK_ARTIFACTS"].map { URL(filePath: $0) }
            ?? store.root.deletingLastPathComponent().appending(path: ".build/swiftbook")
        self.base = base
        if Self.cleared.withLock({ $0.insert(base).inserted }) {
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
        let page = base.appending(path: "review/index.html")
        try ReviewPage.write(ReviewPage.savedEntries(under: base), to: page)
        return page
    }
}
