import Messages
import SwiftUI
import UIKit

/// A SwiftUI view that can act as the root of a Messages extension.
///
/// The `init()` requirement lets ``MessagesAppHost`` construct your root view itself, which is
/// what makes the one-line subclass possible. If your root needs constructor arguments,
/// override ``MessagesAppHost/makeRootView()`` instead of conforming here.
public protocol MessagesRootView: View {
    init()
}

/// Hosts a SwiftUI view inside a Messages extension.
///
/// `NSExtensionPrincipalClass` in your `Info.plist` needs a concrete `@objc` class name, so
/// some subclass is unavoidable. This one is generic over your root view, so the subclass is a
/// single line:
///
/// ```swift
/// @objc(MessagesViewController)
/// final class MessagesViewController: MessagesAppHost<MyRootView> {}
/// ```
///
/// The `@MessagesApp` macro generates exactly that. Nothing here is `final` or private on the
/// way down — override ``makeRootView()``, ``transcriptContentSize``, or any
/// `MSMessagesAppViewController` method, and `super` forwarding stays intact.
///
/// ## Lifetime
///
/// Unlike UIKit Messages extensions, which typically tear down and rebuild child view
/// controllers on every presentation change, this host keeps one `UIHostingController` for its
/// whole life and lets SwiftUI diff the tree. That's what makes
/// ``MessagesPresentationMultiplexableView`` work — the transition becomes a state change
/// rather than a teardown.
@MainActor
open class MessagesAppHost<Root: MessagesRootView>: MSMessagesAppViewController {

    /// This instance's session. Never shared with the extension's other instances.
    public var session: MessagesSession {
        if let storedSession { return storedSession }
        let created = MessagesSession(host: self)
        storedSession = created
        return created
    }

    private var storedSession: MessagesSession?

    /// The hosting controller wrapping your root view, once `viewDidLoad` has run.
    ///
    /// Exposed for the things only UIKit can do — safe area insets, keyboard avoidance,
    /// background colour beyond ``hostBackgroundColor``.
    public private(set) var hostingController: UIHostingController<MessagesRootContainer<Root>>?

    /// Builds the root view. Defaults to `Root()`.
    ///
    /// Override when your root view needs arguments:
    ///
    /// ```swift
    /// override func makeRootView() -> MyRootView {
    ///     MyRootView(store: .shared)
    /// }
    /// ```
    open func makeRootView() -> Root {
        Root()
    }

    /// The size of your message's bubble in the transcript, or `nil` to let Messages decide.
    ///
    /// Only consulted for transcript presentations — `contentSizeThatFits(_:)` is documented as
    /// being called only when the presentation style is `.transcript`, which is why this is
    /// named for the transcript rather than for compact presentation.
    open var transcriptContentSize: CGSize? { nil }

    /// Background colour for the host and hosting views.
    ///
    /// Worth setting even though SwiftUI paints your content: the UIKit views underneath show
    /// through around safe-area edges during transitions. `nil` leaves both untouched.
    open var hostBackgroundColor: UIColor? { nil }

    // MARK: - Setup

    open override func viewDidLoad() {
        super.viewDidLoad()

        if let hostBackgroundColor {
            view.backgroundColor = hostBackgroundColor
        }

        let hosting = UIHostingController(
            rootView: MessagesRootContainer(session: session, root: makeRootView())
        )
        hosting.view.backgroundColor = hostBackgroundColor
        hosting.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(hosting)
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        hosting.didMove(toParent: self)

        self.hostingController = hosting
    }

    open override func contentSizeThatFits(_ size: CGSize) -> CGSize {
        transcriptContentSize ?? super.contentSizeThatFits(size)
    }

    // MARK: - Activation

    open override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        session.hostWillBecomeActive(with: conversation)
    }

    open override func didBecomeActive(with conversation: MSConversation) {
        super.didBecomeActive(with: conversation)
        session.hostDidBecomeActive(with: conversation)
    }

    open override func willResignActive(with conversation: MSConversation) {
        super.willResignActive(with: conversation)
        session.hostWillResignActive(with: conversation)
    }

    open override func didResignActive(with conversation: MSConversation) {
        super.didResignActive(with: conversation)
        session.hostDidResignActive(with: conversation)
    }

    // MARK: - Compact and expanded presentation only

    // Messages does not deliver anything below to a transcript presentation, or when the
    // extension was launched over media.

    open override func willSelect(_ message: MSMessage, conversation: MSConversation) {
        super.willSelect(message, conversation: conversation)
        session.hostWillSelect(message, in: conversation)
    }

    open override func didSelect(_ message: MSMessage, conversation: MSConversation) {
        super.didSelect(message, conversation: conversation)
        session.hostDidSelect(message, in: conversation)
    }

    open override func didReceive(_ message: MSMessage, conversation: MSConversation) {
        super.didReceive(message, conversation: conversation)
        session.hostDidReceive(message, in: conversation)
    }

    open override func didStartSending(_ message: MSMessage, conversation: MSConversation) {
        super.didStartSending(message, conversation: conversation)
        session.hostDidStartSending(message, in: conversation)
    }

    open override func didCancelSending(_ message: MSMessage, conversation: MSConversation) {
        super.didCancelSending(message, conversation: conversation)
        session.hostDidCancelSending(message, in: conversation)
    }

    open override func willTransition(to presentationStyle: MSMessagesAppPresentationStyle) {
        super.willTransition(to: presentationStyle)
        session.hostWillTransition(to: presentationStyle)
    }

    open override func didTransition(to presentationStyle: MSMessagesAppPresentationStyle) {
        super.didTransition(to: presentationStyle)
        session.hostDidTransition(to: presentationStyle)
    }
}
