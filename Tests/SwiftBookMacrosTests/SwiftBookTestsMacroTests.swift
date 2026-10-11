import SwiftBookMacros
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing

@Suite struct SwiftBookTestsMacroTests {
    func expect(
        _ source: String, expandsTo expected: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        assertMacroExpansion(
            source, expandedSource: expected,
            macroSpecs: ["SwiftBookTests": MacroSpec(type: SwiftBookTestsMacro.self)],
            failureHandler: {
                Issue.record(Comment(rawValue: $0.message), sourceLocation: sourceLocation)
            })
    }

    func expansion(excluding: String = "[]", arguments: String = "") -> String {
        """
        struct SwiftBookSnapshots {
            @Testing.Test(
                "References are images",
                .enabled(if: SwiftBookTesting.SwiftBook.canSnapshot, "iOS and tvOS snapshots run through `swiftbook test`")
            )
            func references() {
                if let problem = SwiftBookTesting.SwiftBook.lfsProblem(filePath: #filePath) {
                    Testing.Issue.record(Testing.Comment(rawValue: problem))
                }
            }

            @Testing.Test(
                "Snapshot",
                .enabled(if: SwiftBookTesting.SwiftBook.canSnapshot, "iOS and tvOS snapshots run through `swiftbook test`"),
                .enabled(if: SwiftBookTesting.SwiftBook.lfsProblem(filePath: #filePath) == nil, "references are Git LFS pointers; see \\"References are images\\""),
                arguments: await SwiftBookTesting.SwiftBook.stories(excluding: \(excluding))
            )
            func snapshot(_ story: SwiftBookTesting.TestStory) async throws {
                try await SwiftBookTesting.SwiftBook.verify(story, filePath: #filePath\(arguments))
            }
        }
        """
    }

    @Test func expandsWithDefaults() {
        expect("#SwiftBookTests", expandsTo: expansion())
        expect("#SwiftBookTests()", expandsTo: expansion())
    }

    @Test func passesArgumentsThrough() {
        expect(
            #"#SwiftBookTests(variants: .lightAndDark, excluding: ["M/G/N"])"#,
            expandsTo: expansion(
                excluding: #"["M/G/N"]"#,
                arguments: #", variants: .lightAndDark, excluding: ["M/G/N"]"#))
    }
}
