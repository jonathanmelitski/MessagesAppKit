/// Binds a SwiftUI view to this target as its Messages extension entry point.
///
/// ```swift
/// @MessagesApp
/// struct MyMessagesApp {
///     var body: some View { HomeView() }
/// }
/// ```
///
/// Expands to a `MessagesRootView` conformance plus:
///
/// ```swift
/// @objc(MessagesViewController)
/// final class MessagesViewController: MessagesAppKit.MessagesAppHost<MyMessagesApp> {}
/// ```
///
/// `MessagesViewController` is the class name Xcode's iMessage Extension template already puts
/// in `NSExtensionPrincipalClass`, so nothing in `Info.plist` needs to change.
///
/// This is sugar and nothing depends on it. If you need a different principal class name, or
/// want to override `MSMessagesAppViewController` methods, write the subclass out instead —
/// it's the same one line plus a body. See ``MessagesAppHost``.
///
/// The attached type must be a `struct` with a `body` property and no stored properties that
/// lack defaults, since the macro relies on a synthesized `init()`.
@attached(extension, conformances: MessagesRootView)
@attached(peer, names: named(MessagesViewController))
public macro MessagesApp() = #externalMacro(
    module: "MessagesAppKitMacros",
    type: "MessagesAppMacro"
)
