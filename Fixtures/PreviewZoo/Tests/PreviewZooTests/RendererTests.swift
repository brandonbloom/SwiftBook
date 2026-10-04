#if os(macOS)
    import Foundation
    import SwiftBookCore
    import Testing

    @MainActor @Suite struct RendererTests {
        let stories = Story.all().filter { $0.id.module == "PreviewZoo" }

        func story(_ group: String, _ name: String) throws -> Story {
            try #require(stories.first { $0.id.group == group && $0.id.name == name })
        }

        func environment(_ appearance: RenderEnvironment.Appearance, scale: Double = 2)
            -> RenderEnvironment
        {
            var environment = RenderEnvironment()
            environment.appearance = appearance
            environment.scale = scale
            return environment
        }

        @Test(arguments: [("Card", "Card"), ("Hazards", "Material and blur"), ("Hazards", "List")])
        func rendersIdenticallyEveryTime(group: String, name: String) async throws {
            let story = try story(group, name)
            let first = try await MacRenderer.render(story).pngData()
            for _ in 1..<10 {
                #expect(try await MacRenderer.render(story).pngData() == first)
            }
        }

        @Test func lightAndDarkDiffer() async throws {
            let story = try story("Card", "Card")
            let light = try await MacRenderer.render(story, in: environment(.light)).pngData()
            let dark = try await MacRenderer.render(story, in: environment(.dark)).pngData()
            #expect(light != dark)
        }

        @Test func sizesFromLayoutTraits() async throws {
            let fixed = try await MacRenderer.render(try story("Layouts", "Fixed layout")).image
            #expect((fixed.width, fixed.height) == (400, 160))
            let device = try await MacRenderer.render(try story("Layouts", "Default layout")).image
            #expect((device.width, device.height) == (1600, 1200))
            let modified = try await MacRenderer.render(
                try story("SharedContext", "Modifier with stored properties"))
            #expect(modified.image.width == 600)
        }

        @Test func rendersAtTheRequestedScale() async throws {
            let image = try await MacRenderer.render(
                try story("Layouts", "Fixed layout"), in: environment(.light, scale: 1)
            )
            .image
            #expect((image.width, image.height) == (200, 80))
        }

        @Test func pinsTheTimeZone() async throws {
            let story = try story("Hazards", "Foundation-formatted date")
            var tokyo = RenderEnvironment()
            tokyo.timeZoneIdentifier = "Asia/Tokyo"
            let utc = try await MacRenderer.render(story).pngData()
            #expect(try await MacRenderer.render(story, in: tokyo).pngData() != utc)
            #expect(try await MacRenderer.render(story).pngData() == utc)
        }

        @Test func storesMetadataInThePNG() async throws {
            let png = try await MacRenderer.render(
                try story("Card", "Card"), in: environment(.dark)
            ).pngData()
            let metadata = try #require(try SnapshotMetadata.read(fromPNG: png))
            #expect(metadata.story == "PreviewZoo/Card/Card")
            #expect(metadata.platform == "macOS")
            #expect(metadata.appearance == "dark")
            #expect(metadata.scale == 2)
            #expect(metadata.timeZone == "UTC")
        }

        /// Renders every story, light and dark, into `$SWIFTBOOK_ARTIFACTS` for people to look at.
        @Test(.enabled(if: ProcessInfo.processInfo.environment["SWIFTBOOK_ARTIFACTS"] != nil))
        func writesArtifacts() async throws {
            let directory = URL(
                filePath: ProcessInfo.processInfo.environment["SWIFTBOOK_ARTIFACTS"]!)
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            for story in stories {
                for appearance in RenderEnvironment.Appearance.allCases {
                    let png = try await MacRenderer.render(story, in: environment(appearance))
                        .pngData()
                    let name = "\(story.id.group)--\(story.id.name)--\(appearance)".replacing(
                        "/", with: "∕")
                    try png.write(to: directory.appending(path: "\(name).png"))
                }
            }
        }
    }
#endif
