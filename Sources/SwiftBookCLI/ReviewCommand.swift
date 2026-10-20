#if os(macOS)
    import ArgumentParser
    import Foundation
    import SwiftBookCore

    /// `swiftbook review`: shows the review page from the last `swift test` run.
    struct ReviewCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "review",
            abstract: "Open the page of references recorded or failed by the last test run.",
            discussion: """
                swift test writes the page whenever it records or fails a reference. Set \
                SWIFTBOOK_ARTIFACTS if the tests did.
                """)

        @Flag(help: "Print the page's path instead of opening it.")
        var print = false

        @Option(
            help: ArgumentHelp(
                "Write the page to this file, with its images inside it, instead of opening it.",
                discussion: "One file, to send to someone or open on a phone.",
                valueName: "file"))
        var export: String?

        @Option(
            name: [.customLong("device"), .customLong("platform")],
            help: ArgumentHelp(
                "With --export, only this device's references: mac, iphone, ipad, or tv. Repeat for several.",
                valueName: "device"))
        var devices: [Device] = []

        @Option(help: "With --export, only light or dark references.")
        var appearance: RenderEnvironment.Appearance?

        func run() throws {
            let page: URL
            do {
                page = Self.page(for: try Project.current())
            } catch let failure as Failure {
                warn("swiftbook: \(failure)")
                throw Exit.broken.code
            }
            guard FileManager.default.fileExists(atPath: page.path) else {
                warn(
                    "swiftbook: no review page at \(page.path). swift test writes one when it records or fails a reference."
                )
                throw Exit.broken.code
            }
            if let export {
                let artifacts = page.deletingLastPathComponent().deletingLastPathComponent()
                do {
                    try ReviewPage.write(
                        ReviewPage.savedEntries(under: artifacts).filter {
                            VariantFilter(devices: devices, appearance: appearance)
                                .includes($0.variant)
                        }, to: URL(filePath: export),
                        inlineImages: true)
                } catch {
                    warn("swiftbook: couldn't write \(export): \(error)")
                    throw Exit.broken.code
                }
            } else if print {
                Swift.print(page.path)
            } else if Shell.run(["open", page.path])?.succeeded != true {
                warn("swiftbook: couldn't open \(page.path)")
                throw Exit.broken.code
            }
        }

        /// Where `swift test` writes the review page for `project`.
        static func page(for project: Project) -> URL {
            (ProcessInfo.processInfo.environment["SWIFTBOOK_ARTIFACTS"].map { URL(filePath: $0) }
                ?? project.root.appending(path: ".build/swiftbook"))
                .appending(path: "review/index.html")
        }
    }
#endif
