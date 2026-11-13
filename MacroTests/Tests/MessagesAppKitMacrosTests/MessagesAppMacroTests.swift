import MessagesAppKitMacros
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

// The conformance list has to be stated here. At compile time Swift reads it off the macro's
// `@attached(extension, conformances:)` declaration, but the test harness only sees the
// implementation type, so without this `protocols` arrives empty and no extension is generated.
private let macros: [String: MacroSpec] = [
    "MessagesApp": MacroSpec(
        type: MessagesAppMacro.self,
        conformances: ["MessagesAppKit.MessagesRootView"]
    )
]

final class MessagesAppMacroTests: XCTestCase {

    func testGeneratesPrincipalClassAndConformance() {
        assertMacroExpansion(
            """
            @MessagesApp
            struct MyApp {
                var body: some View { Text("hi") }
            }
            """,
            expandedSource: """
            struct MyApp {
                var body: some View { Text("hi") }
            }

            @objc(MessagesViewController)
            final class MessagesViewController: MessagesAppKit.MessagesAppHost<MyApp> {
            }

            extension MyApp: MessagesAppKit.MessagesRootView {
            }
            """,
            macroSpecs: macros
        )
    }

    func testStoredPropertiesWithDefaultsAreAllowed() {
        assertMacroExpansion(
            """
            @MessagesApp
            struct MyApp {
                var count = 0
                var computed: Int { count + 1 }
                var body: some View { Text("hi") }
            }
            """,
            expandedSource: """
            struct MyApp {
                var count = 0
                var computed: Int { count + 1 }
                var body: some View { Text("hi") }
            }

            @objc(MessagesViewController)
            final class MessagesViewController: MessagesAppKit.MessagesAppHost<MyApp> {
            }

            extension MyApp: MessagesAppKit.MessagesRootView {
            }
            """,
            macroSpecs: macros
        )
    }

    func testRejectsNonStruct() {
        assertMacroExpansion(
            """
            @MessagesApp
            class MyApp {
                var body: some View { Text("hi") }
            }
            """,
            expandedSource: """
            class MyApp {
                var body: some View { Text("hi") }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'@MessagesApp' can only be attached to a struct",
                    line: 1,
                    column: 1
                )
            ],
            macroSpecs: macros
        )
    }

    func testRejectsMissingBody() {
        assertMacroExpansion(
            """
            @MessagesApp
            struct MyApp {
                var title = "hi"
            }
            """,
            expandedSource: """
            struct MyApp {
                var title = "hi"
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                        "'@MessagesApp' requires a 'body' property returning the extension's root view",
                    line: 1,
                    column: 1
                )
            ],
            macroSpecs: macros
        )
    }

    func testRejectsStoredPropertyWithoutDefault() {
        assertMacroExpansion(
            """
            @MessagesApp
            struct MyApp {
                var store: Store
                var body: some View { Text("hi") }
            }
            """,
            expandedSource: """
            struct MyApp {
                var store: Store
                var body: some View { Text("hi") }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: """
                        '@MessagesApp' requires every stored property to have a default value, but \
                        'store' has none. The extension is instantiated by the system, so its root \
                        view must be constructible with 'init()'. Give 'store' a default, or \
                        override 'makeRootView()' on a hand-written 'MessagesAppHost' subclass \
                        instead.
                        """,
                    line: 3,
                    column: 9
                )
            ],
            macroSpecs: macros
        )
    }
}
