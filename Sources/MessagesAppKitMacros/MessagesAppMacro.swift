import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// Implements `@MessagesApp`.
///
/// Emits the `@objc` subclass that `NSExtensionPrincipalClass` names, plus the
/// `MessagesRootView` conformance. The generated class name is fixed rather than configurable:
/// `MessagesViewController` is what Xcode's template already writes into `Info.plist`, and a
/// peer macro has to declare the names it introduces. Anyone needing a different name writes
/// the subclass by hand, which is the one line this macro generates.
public struct MessagesAppMacro {

    /// The class name written into `Info.plist` by Xcode's iMessage Extension template.
    static let generatedClassName = "MessagesViewController"

    enum Validation {
        case valid(StructDeclSyntax)
        case invalid(Diagnostic)
    }

    /// Checks the declaration can support the generated code, so a mistake surfaces as a clear
    /// diagnostic on the attribute rather than a confusing error inside expanded source.
    ///
    /// Returns the diagnostic instead of emitting it, because this type fills two macro roles and
    /// both need the check. Only the peer role reports, or every mistake would be flagged twice.
    static func validate(
        _ declaration: some DeclSyntaxProtocol,
        attribute node: AttributeSyntax
    ) -> Validation {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            return .invalid(Diagnostic(node: node, message: MacroDiagnostic.notAStruct))
        }

        let variables = structDecl.memberBlock.members
            .compactMap { $0.decl.as(VariableDeclSyntax.self) }

        // `MessagesAppHost` constructs the root view with `Root()`, which only exists if every
        // stored property carries a default.
        for variable in variables {
            for binding in variable.bindings {
                let isStored = binding.accessorBlock == nil
                let hasDefault = binding.initializer != nil
                guard isStored, !hasDefault else { continue }
                let name = binding.pattern.trimmedDescription
                return .invalid(
                    Diagnostic(
                        node: binding,
                        message: MacroDiagnostic.storedPropertyWithoutDefault(name: name)
                    )
                )
            }
        }

        let hasBody = variables.contains { variable in
            variable.bindings.contains { binding in
                binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "body"
            }
        }
        guard hasBody else {
            return .invalid(Diagnostic(node: node, message: MacroDiagnostic.missingBody))
        }

        return .valid(structDecl)
    }
}

extension MessagesAppMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let structDecl: StructDeclSyntax
        switch validate(declaration, attribute: node) {
        case .valid(let decl):
            structDecl = decl
        case .invalid(let diagnostic):
            // The peer role is the one that reports. See `validate`.
            context.diagnose(diagnostic)
            return []
        }
        let rootName = structDecl.name.trimmed

        return [
            """
            @objc(\(raw: generatedClassName))
            final class \(raw: generatedClassName): MessagesAppKit.MessagesAppHost<\(rootName)> {}
            """
        ]
    }
}

extension MessagesAppMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        // Empty when the type already declares the conformance itself.
        guard !protocols.isEmpty else { return [] }
        // Silently, because the peer role has already diagnosed this same failure.
        guard case .valid = validate(declaration, attribute: node) else { return [] }

        let decl: DeclSyntax =
            "extension \(type.trimmed): MessagesAppKit.MessagesRootView {}"
        return [decl.cast(ExtensionDeclSyntax.self)]
    }
}

enum MacroDiagnostic: DiagnosticMessage {
    case notAStruct
    case missingBody
    case storedPropertyWithoutDefault(name: String)

    var message: String {
        switch self {
        case .notAStruct:
            "'@MessagesApp' can only be attached to a struct"
        case .missingBody:
            "'@MessagesApp' requires a 'body' property returning the extension's root view"
        case .storedPropertyWithoutDefault(let name):
            """
            '@MessagesApp' requires every stored property to have a default value, but '\(name)' \
            has none. The extension is instantiated by the system, so its root view must be \
            constructible with 'init()'. Give '\(name)' a default, or override \
            'makeRootView()' on a hand-written 'MessagesAppHost' subclass instead.
            """
        }
    }

    var severity: DiagnosticSeverity { .error }

    var diagnosticID: MessageID {
        switch self {
        case .notAStruct:
            MessageID(domain: "MessagesAppKit", id: "notAStruct")
        case .missingBody:
            MessageID(domain: "MessagesAppKit", id: "missingBody")
        case .storedPropertyWithoutDefault:
            MessageID(domain: "MessagesAppKit", id: "storedPropertyWithoutDefault")
        }
    }
}
