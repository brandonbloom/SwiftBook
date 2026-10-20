// Snapshot testing of discovered stories under Swift Testing.

import Foundation
@_exported import SwiftBookCore
import Synchronization
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

    /// Why the project's references can't be used, if any are Git LFS pointers. `#SwiftBookTests`
    /// reports it once, and skips the snapshots, rather than failing every one.
    ///
    /// - Parameter filePath: A file in the project, which locates its `Snapshots/` directory.
    public static func lfsProblem(filePath: String) -> String? {
        lfsProblems.withLock { cache in
            if let known = cache[filePath] { return known }
            let problem = (try? SnapshotStore.forProject(containing: filePath))?.lfsProblem()
            cache[filePath] = .some(problem)
            return problem
        }
    }

    /// Checked once per file per run: the scan reads every reference.
    private static let lfsProblems = Mutex<[String: String?]>([:])

    /// Every story in this process, except `excluded` ones (as `Module/Group/Name`) and those
    /// the package's `SwiftBookConfiguration` excludes.
    public static func stories(excluding excluded: Set<String> = []) async -> [TestStory] {
        await MainActor.run {
            let excluded = excluded.union(ProjectConfiguration.excluded)
            return Story.all().filter { !excluded.contains($0.id.description) }
                .map(TestStory.init)
        }
    }

    /// Renders each variant of `story` and checks it against its reference, recording an issue
    /// for every variant that fails.
    ///
    /// - Parameters:
    ///   - story: The story to snapshot.
    ///   - filePath: A file in the project, which locates its `Snapshots/` directory.
    ///   - variants: The variants to render and verify.
    ///   - tolerance: What counts as a change.
    ///   - excluding: Ignored here; `#SwiftBookTests` passes it to ``stories(excluding:)``.
    ///   - store: Overrides where references live.
    ///   - mode: Overrides `SWIFTBOOK_RECORD`.
    ///   - sourceLocation: Where to report failures.
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
        guard
            let report = try SnapshotReport(
                verification, of: snapshot, mode: mode, store: store, hints: .swiftTest)
        else { return }
        for image in report.images {
            if let data = try? Data(contentsOf: URL(filePath: image.path)) {
                Attachment.record(data, named: "\(report.variant).\(image.role).png")
            }
        }
        Issue.record(
            Comment(rawValue: report.message),
            severity: report.severity == .failure ? .error : .warning,
            sourceLocation: sourceLocation)
    }
}
