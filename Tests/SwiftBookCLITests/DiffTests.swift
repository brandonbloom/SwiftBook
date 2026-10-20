#if os(macOS)
    import CoreGraphics
    import Foundation
    import ImageIO
    import SwiftBookCore
    import Testing
    import UniformTypeIdentifiers

    @testable import SwiftBookCLI

    /// `swiftbook diff` against a scratch package whose references are committed.
    @Suite struct DiffTests {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "DiffTests-\(UUID())", directoryHint: .isDirectory)

        @discardableResult
        func git(_ arguments: String...) throws -> String {
            let result = try #require(
                Shell.run(
                    [
                        "git", "-c", "user.name=Test", "-c", "user.email=test@example.com",
                        "-c", "commit.gpgsign=false", "-c", "init.defaultBranch=main",
                    ] + arguments,
                    in: directory,
                    environment: ["GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"]))
            try #require(result.succeeded, "git \(arguments) failed: \(result.error)")
            return result.output
        }

        /// A 10×10 PNG of one gray.
        func png(gray: UInt8) throws -> Data {
            let context = try #require(
                CGContext(
                    data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(gray: Double(gray) / 255, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
            let data = NSMutableData()
            let destination = try #require(
                CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
            try #require(CGImageDestinationFinalize(destination))
            return data as Data
        }

        func write(_ data: Data, to path: String) throws {
            let url = directory.appending(path: "Snapshots/\(path)")
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }

        /// A package with four committed references, then changed in the working tree.
        func changedProject() throws -> (Project, GitRepository) {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            try Data("// swift-tools-version: 6.2\n".utf8).write(
                to: directory.appending(path: "Package.swift"))
            try git("init", "-q")
            for name in ["Kept", "Changed", "Nudged", "Deleted"] {
                try write(png(gray: 100), to: "M/G/\(name)/mac.light.png")
            }
            try git("add", "-A")
            try git("commit", "-q", "-m", "references")
            try write(png(gray: 200), to: "M/G/Changed/mac.light.png")
            try write(png(gray: 101), to: "M/G/Nudged/mac.light.png")
            try FileManager.default.removeItem(
                at: directory.appending(path: "Snapshots/M/G/Deleted/mac.light.png"))
            try write(png(gray: 50), to: "M/G/Added/mac.dark.png")
            let project = try Project(containing: directory)
            return (project, try #require(project.repository))
        }

        @Test func findsAddedDeletedAndModifiedReferences() throws {
            let (project, repository) = try changedProject()
            let changes = try project.store.changes(since: "HEAD", in: repository)
            #expect(
                changes.map(\.story) == ["M/G/Added", "M/G/Changed", "M/G/Deleted", "M/G/Nudged"])
            #expect(changes.map(\.kind) == [.added, .modified, .deleted, .modified])
            #expect(changes.allSatisfy { $0.variant.hasPrefix("mac.") })
            // A change within tolerance is listed but doesn't count.
            #expect(changes.map(\.isSignificant) == [true, true, true, false])
            #expect(changes[1].diff?.changedPixels == 100)
            #expect(changes[2].previous == (try png(gray: 100)))
        }

        @Test func setsReencodedReferencesAside() throws {
            let (project, repository) = try changedProject()
            // As swiftbook compress leaves it: the same image, encoded differently.
            let kept = directory.appending(path: "Snapshots/M/G/Kept/mac.light.png")
            let compaction = try project.store.compact(kept)
            try #require(compaction.after < compaction.before)

            let changes = try project.store.changes(since: "HEAD", in: repository)
            #expect(changes.first { $0.story == "M/G/Kept" }?.kind == .reencoded)
            #expect(changes.first { $0.story == "M/G/Nudged" }?.kind == .modified)
            let human = DiffCommand.human(changes, against: "HEAD (abc)")
            #expect(human.hasPrefix("4 references changed against HEAD (abc):"))
            #expect(!human.contains("M/G/Kept"))
            #expect(
                human.hasSuffix(
                    "\n1 more reference was re-encoded, with the same pixels and metadata."))
            #expect(
                DiffCommand.human(changes.filter { $0.kind == .reencoded }, against: "HEAD")
                    == "No references changed against HEAD.\n1 reference was re-encoded, with the same pixels and metadata."
            )
            #expect(
                try DiffCommand.json(changes, revision: "HEAD", commit: "abc").contains("reencoded")
            )
        }

        @Test func comparesAgainstTheMergeBase() throws {
            let (_, repository) = try changedProject()
            try git("checkout", "-q", "-b", "feature")
            try git("add", "-A")
            try git("commit", "-q", "-m", "feature")
            let project = try Project(containing: directory)
            #expect(
                try project.store.changes(since: repository.mergeBase("main"), in: repository).count
                    == 4)
            #expect(
                try project.store.changes(since: repository.resolve("HEAD"), in: repository).isEmpty
            )
        }

        @Test func printsEachFormat() throws {
            let (project, repository) = try changedProject()
            let changes = try project.store.changes(since: "HEAD", in: repository)
            let human = DiffCommand.human(changes, against: "HEAD (abc)")
            #expect(human.hasPrefix("4 references changed against HEAD (abc):\n  added "))
            #expect(human.contains("M/G/Changed  mac.light  100 pixels (100%), max ΔE"))
            #expect(human.contains("M/G/Nudged   mac.light  within tolerance"))

            let json = try DiffCommand.json(changes, revision: "HEAD", commit: "abc")
            let decoded = try #require(
                JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
            #expect((decoded["changes"] as? [Any])?.count == 4)

            let junit = DiffCommand.junit(changes, against: "HEAD (abc)")
            #expect(junit.contains(#"tests="4" failures="3""#))
            #expect(
                junit.contains(#"<testcase classname="M/G/Nudged" name="M/G/Nudged (mac.light)"/>"#)
            )
        }

        @Test func writesAPageOfChanges() throws {
            let (project, repository) = try changedProject()
            let changes = try project.store.changes(since: "HEAD", in: repository)
            let page = try DiffCommand.writePage(changes, project: project, against: "HEAD")
            let html = try String(contentsOf: page, encoding: .utf8)
            #expect(html.contains("Against HEAD: 1 new · 2 re-recorded · 1 deleted"))
            #expect(html.contains("images/M/G/Changed/mac.light.before.png"))
            #expect(html.contains("images/M/G/Changed/mac.light.diff.png"))
        }

        @Test func filtersVariantsByDeviceAndAppearance() {
            let all = VariantFilter(devices: [], appearance: nil)
            #expect(all.includes("mac.light"))
            let iPhoneDark = VariantFilter(devices: [.iphone], appearance: .dark)
            #expect(iPhoneDark.includes("iphone.dark"))
            #expect(iPhoneDark.includes("iphone.dark.rtl"))
            #expect(!iPhoneDark.includes("iphone.light"))
            #expect(!iPhoneDark.includes("mac.dark"))
            let macOrTV = VariantFilter(devices: [.mac, .tv], appearance: nil)
            #expect(macOrTV.includes("tv.light") && macOrTV.includes("mac.dark"))
            #expect(!macOrTV.includes("ipad.dark"))
        }
    }
#endif
