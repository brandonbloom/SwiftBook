import Foundation

/// Finds snapshots that render differently from run to run, by grouping repeated renders of each
/// one into variants. It needs no references: a render only has to disagree with itself.
package struct FlakeFinder: Sendable {
    /// One way a snapshot rendered, and how often.
    package struct Variant: Sendable {
        package let png: Data
        package let glassRegions: [ImageDiff.PixelRect]
        package internal(set) var count: Int
    }

    /// A snapshot that rendered more than one way, or failed in some runs.
    package struct Flake: @unchecked Sendable {
        // Unchecked: ImageDiff holds immutable CGImages.

        package let subject: String
        /// The ways it rendered, most common first.
        package let variants: [Variant]
        /// How each other variant differs from the most common one, in order, as a snapshot
        /// comparison would see it: with the default tolerance, glass included.
        package let differences: [ImageDiff]
        /// How each other variant differs at all, in order: every differing pixel, with no
        /// tolerance. Shows where a difference too faint to fail a comparison is.
        package let exactDifferences: [ImageDiff]
        /// Runs in which it failed to render, and the first failure.
        package let failures: Int
        package let failure: String?

        /// Whether a snapshot comparison could fail on it: a variant differs beyond the tolerance,
        /// or a render failed.
        package var wouldFail: Bool {
            failures > 0 || differences.contains { !$0.matches }
        }
    }

    private var subjects: [String] = []
    private var variants: [String: [Variant]] = [:]
    private var failures: [String: (count: Int, first: String)] = [:]

    package init() {}

    /// Records one run's render of `subject`.
    package mutating func add(
        _ png: Data, glassRegions: [ImageDiff.PixelRect] = [], for subject: String
    ) {
        note(subject)
        if let index = variants[subject, default: []].firstIndex(where: { $0.png == png }) {
            variants[subject]![index].count += 1
        } else {
            variants[subject, default: []].append(
                Variant(png: png, glassRegions: glassRegions, count: 1))
        }
    }

    /// Records that `subject` failed to render in one run.
    package mutating func addFailure(_ error: String, for subject: String) {
        note(subject)
        if let existing = failures[subject] {
            failures[subject] = (existing.count + 1, existing.first)
        } else {
            failures[subject] = (1, error)
        }
    }

    private mutating func note(_ subject: String) {
        if variants[subject] == nil, failures[subject] == nil { subjects.append(subject) }
    }

    /// Every snapshot that rendered more than one way, or rendered in some runs and failed in
    /// others, in the order they were first seen.
    package func flakes() throws -> [Flake] {
        try subjects.compactMap { subject in
            let variants = (variants[subject] ?? []).sorted { $0.count > $1.count }
            let failures = failures[subject]
            // Consistent: one way every time, or failing every time.
            guard variants.count > 1 || (failures != nil && !variants.isEmpty) else {
                return nil
            }
            let first = try SnapshotStore.image(variants[0].png, at: subject)
            var exact = ImageDiff.Tolerance()
            exact.deltaE = 0
            exact.ignoresAntialiasing = false
            var differences: [ImageDiff] = []
            var exactDifferences: [ImageDiff] = []
            for variant in variants.dropFirst() {
                let image = try SnapshotStore.image(variant.png, at: subject)
                differences.append(
                    try ImageDiff.compare(
                        expected: first, actual: image, glass: variant.glassRegions))
                exactDifferences.append(
                    try ImageDiff.compare(expected: first, actual: image, tolerance: exact))
            }
            return Flake(
                subject: subject, variants: variants, differences: differences,
                exactDifferences: exactDifferences, failures: failures?.count ?? 0,
                failure: failures?.first)
        }
    }
}
