import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct MessagesAppKitPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        MessagesAppMacro.self
    ]
}
