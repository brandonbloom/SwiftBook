import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct SwiftBookMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = []
}
