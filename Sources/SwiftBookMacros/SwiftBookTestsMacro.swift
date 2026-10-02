import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `#SwiftBookTests(...)`: a Swift Testing suite with one test case per story.
///
/// The macro's arguments pass straight through to `SwiftBook.verify`, which declares the same
/// parameters and defaults; `excluding:` also filters the stories.
public struct SwiftBookTestsMacro: DeclarationMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax, in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let arguments = node.arguments.map { argument in
            argument.with(\.trailingComma, nil).trimmedDescription
        }
        let excluding = node.arguments.first { $0.label?.text == "excluding" }?.expression
            .trimmedDescription
        let passedArguments = arguments.map { ", \($0)" }.joined()
        return [
            """
            struct SwiftBookSnapshots {
                @Testing.Test(
                    "Snapshot",
                    .enabled(if: SwiftBookTesting.SwiftBook.canSnapshot, "iOS and tvOS snapshots run through `swiftbook test`"),
                    arguments: await SwiftBookTesting.SwiftBook.stories(excluding: \(raw: excluding ?? "[]"))
                )
                func snapshot(_ story: SwiftBookTesting.TestStory) async throws {
                    try await SwiftBookTesting.SwiftBook.verify(story, filePath: #filePath\(raw: passedArguments))
                }
            }
            """
        ]
    }
}
