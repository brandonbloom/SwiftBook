import CoreGraphics
import Foundation
import ImageIO

/// When references are written instead of compared.
public enum RecordMode: String, Hashable, Sendable, CaseIterable {
    /// Record references that don't exist yet; compare the rest. The default.
    case missing
    /// Also re-record references that no longer match.
    case changed
    /// Re-record every reference.
    case all
    /// Never record; a missing reference is a failure. For CI.
    case never

    /// The variable that sets the record mode.
    public static let environmentVariable = "SWIFTBOOK_RECORD"

    /// The mode set by `SWIFTBOOK_RECORD`, or ``missing`` when unset.
    public static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    )
        throws -> RecordMode
    {
        guard let value = environment[environmentVariable], !value.isEmpty else { return .missing }
        guard let mode = RecordMode(rawValue: value) else {
            let modes = allCases.map(\.rawValue).joined(separator: ", ")
            throw StorageError(description: "\(environmentVariable)=\(value) isn't one of \(modes)")
        }
        return mode
    }
}

/// The result of checking a snapshot against its reference.
public enum Verification: @unchecked Sendable {
    // Unchecked: ImageDiff holds immutable CGImages.

    /// The snapshot matches its reference within the tolerance.
    case matched(ImageDiff)
    /// The reference was written. `previous` compares against the reference it replaced, if any
    /// could be read, and `replaced` is that reference's PNG.
    case recorded(URL, previous: ImageDiff?, replaced: Data?)
    /// The snapshot doesn't match its reference.
    case mismatched(ImageDiff, reference: URL, referenceMetadata: SnapshotMetadata?)
    /// There's no reference, and the record mode doesn't allow writing one.
    case missing(URL)
}

/// A storage error, such as an unreadable reference.
public struct StorageError: Error, CustomStringConvertible, Sendable {
    public let description: String
}

/// Reference images in a package's `Snapshots/` directory:
/// `Snapshots/<Module>/<Group>/<Story>/<device>.<appearance>[.<dimensions>].png`.
public struct SnapshotStore: Sendable {
    /// The `Snapshots` directory.
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// The store for the package or Xcode project containing `filePath`: the nearest enclosing
    /// directory with a `Package.swift` or an `.xcodeproj`.
    public static func forProject(containing filePath: String) throws -> SnapshotStore {
        var directory = URL(filePath: filePath).deletingLastPathComponent()
        let fileManager = FileManager.default
        while directory.path != "/" {
            let contents = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
            if contents.contains("Package.swift")
                || contents.contains(where: { $0.hasSuffix(".xcodeproj") })
            {
                return SnapshotStore(
                    root: directory.appending(path: "Snapshots", directoryHint: .isDirectory))
            }
            directory.deleteLastPathComponent()
        }
        throw StorageError(description: "no Package.swift or .xcodeproj encloses \(filePath)")
    }

    /// Every reference PNG, and those that are Git LFS pointers whose images aren't downloaded.
    public func references() -> (all: [URL], pointers: [URL]) {
        guard
            let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: nil)
        else { return ([], []) }
        var all: [URL] = []
        var pointers: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "png" else { continue }
            all.append(url)
            if let handle = try? FileHandle(forReadingFrom: url),
                let start = try? handle.read(upToCount: GitLFS.pointerPrefix.count),
                GitLFS.isPointer(start)
            {
                pointers.append(url)
            }
        }
        return (all, pointers)
    }

    /// Why the references can't be used, if any are Git LFS pointers: one message for all of
    /// them, rather than a failure for every snapshot.
    public func lfsProblem() -> String? {
        let (all, pointers) = references()
        guard let first = pointers.first else { return nil }
        return
            "\(pointers.count) of \(all.count) references are Git LFS pointers, not images, such as \(first.path). Run: \(GitLFS.fix)"
    }

    /// How `device`'s references were captured, as their metadata names the method, judging by
    /// the first readable one. `nil` if there are none, or it doesn't say.
    public func recordedCapture(on device: Device) -> String? {
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "png",
                url.lastPathComponent.hasPrefix("\(device.rawValue)."),
                let data = try? Data(contentsOf: url),
                let metadata = try? SnapshotMetadata.read(fromPNG: data)
            else { continue }
            return metadata.capture
        }
        return nil
    }

    /// Where the reference for a story rendered on `device` in `environment` lives.
    public func url(for story: StoryID, device: Device, environment: RenderEnvironment) -> URL {
        [story.module, story.group, story.name].reduce(root) { url, component in
            url.appending(path: Self.fileName(component), directoryHint: .isDirectory)
        }
        .appending(path: Self.variantName(device: device, environment: environment) + ".png")
    }

    /// Compares `snapshot` with its reference, recording it as `mode` allows.
    public func verify(
        _ snapshot: Snapshot, mode: RecordMode, tolerance: ImageDiff.Tolerance = .init()
    ) throws
        -> Verification
    {
        let url = url(
            for: snapshot.story, device: snapshot.device, environment: snapshot.environment)
        let png = try snapshot.pngData()
        guard let reference = try? Data(contentsOf: url) else {
            guard mode != .never else { return .missing(url) }
            try write(png, to: url)
            return .recorded(url, previous: nil, replaced: nil)
        }
        // In every mode: recording over a pointer would replace a reference nobody has seen.
        if GitLFS.isPointer(reference) {
            throw StorageError(description: GitLFS.pointerProblem(at: url.path))
        }
        if mode == .all {
            // An identical reference needs no rewrite, so it isn't reported as recorded.
            if reference == png {
                return .matched(
                    try compare(
                        snapshot, toReference: reference, at: url, tolerance: tolerance))
            }
            let previous = try? compare(
                snapshot, toReference: reference, at: url, tolerance: tolerance)
            try write(png, to: url)
            return .recorded(url, previous: previous, replaced: reference)
        }
        let diff = try compare(
            snapshot, toReference: reference, at: url, tolerance: tolerance)
        if diff.matches { return .matched(diff) }
        if mode == .changed {
            try write(png, to: url)
            return .recorded(url, previous: diff, replaced: reference)
        }
        return .mismatched(
            diff, reference: url, referenceMetadata: try? SnapshotMetadata.read(fromPNG: reference))
    }

    private func compare(
        _ snapshot: Snapshot, toReference reference: Data, at url: URL,
        tolerance: ImageDiff.Tolerance
    )
        throws -> ImageDiff
    {
        guard let source = CGImageSourceCreateWithData(reference as CFData, nil),
            let expected = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw StorageError(description: "\(url.path) isn't a readable image") }
        return try ImageDiff.compare(
            expected: expected, actual: snapshot.image, tolerance: tolerance,
            glass: snapshot.glassRegions)
    }

    /// Decodes `png`, naming `path` if it can't.
    public static func image(_ png: Data, at path: String) throws -> CGImage {
        if GitLFS.isPointer(png) {
            throw StorageError(description: GitLFS.pointerProblem(at: path))
        }
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw StorageError(description: "\(path) isn't a readable image") }
        return image
    }

    private func write(_ png: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url, options: .atomic)
    }

    // MARK: Names

    /// A story, group, or module name as one path component: readable, and valid on macOS,
    /// Windows, and Git. Characters reserved by any of them become `_`.
    public static func fileName(_ name: String) -> String {
        let reserved = Set("/\\:*?\"<>|")
        var result = String(
            name.map { reserved.contains($0) || $0.isASCII && $0.asciiValue! < 0x20 ? "_" : $0 })
        // Windows strips trailing dots and spaces; a leading dot would hide the file.
        while result.last == "." || result.last == " " { result.removeLast() }
        if result.first == "." { result = "_" + result.dropFirst() }
        return result.isEmpty ? "_" : result
    }

    /// The file name for a variant: device and appearance, then each other dimension that isn't
    /// at its default, in a fixed order.
    public static func variantName(device: Device, environment: RenderEnvironment) -> String {
        let defaults = RenderEnvironment()
        var parts = [device.rawValue, environment.appearance.rawValue]
        if environment.dynamicTypeSize != defaults.dynamicTypeSize {
            parts.append(String(describing: environment.dynamicTypeSize))
        }
        if environment.layoutDirection != defaults.layoutDirection { parts.append("rtl") }
        if environment.localeIdentifier != defaults.localeIdentifier {
            parts.append(fileName(environment.localeIdentifier))
        }
        return parts.joined(separator: ".")
    }
}
