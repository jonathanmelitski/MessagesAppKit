import Combine
import Foundation
import Messages

/// The state of one running instance of your Messages extension, observable from SwiftUI.
///
/// Reach it with `@EnvironmentObject`; ``MessagesAppHost`` injects it above your root view.
///
/// ```swift
/// struct MyView: View {
///     @EnvironmentObject private var session: MessagesSession
/// }
/// ```
///
/// ## One session per instance, never shared
///
/// Messages runs your `MSMessagesAppViewController` subclass many times over in a single
/// process — one instance per live-layout bubble in the transcript, one for a message staged
/// in the input field, and one for your own interface. Each gets its own `MessagesSession`,
/// and this package holds no `static` mutable state anywhere, so instances cannot corrupt
/// one another.
///
/// The same discipline applies to *your* code. A shared in-memory store would be read and
/// written by every instance at once and go stale immediately. Apple's own `IceCreamBuilder`
/// sample re-reads `UserDefaults` on every single access for exactly this reason, and keeps
/// its one singleton for idempotent derived files only. Check ``role`` when an instance needs
/// to know what it is.
@MainActor
public final class MessagesSession: ObservableObject {

    /// Distinguishes this instance from its siblings in log output.
    ///
    /// Has no meaning to Messages. It exists because several instances logging at once is
    /// otherwise impossible to read.
    public let id = UUID()

    /// Which kind of instance this is. See ``MessagesInstanceRole``.
    @Published public private(set) var role: MessagesInstanceRole

    /// The style currently showing. Constant for the life of a transcript presentation.
    @Published public private(set) var presentationStyle: MSMessagesAppPresentationStyle

    /// The last style the *user* chose, ignoring styles this extension requested.
    ///
    /// Restore it with ``restoreUserPreferredStyle()`` when a task that needed more room is
    /// finished. Meaningless for transcript presentations, which never transition.
    @Published public private(set) var userPreferredStyle: RequestablePresentationStyle

    /// Whether the extension was launched in Messages or over media.
    ///
    /// In ``MSMessagesAppPresentationContext/media`` every staging and sending method is
    /// unavailable, and no ``MessagesInteractionObserver`` callback is delivered.
    @Published public private(set) var presentationContext: MSMessagesAppPresentationContext

    /// The active conversation, once the extension has become active.
    @Published public private(set) var conversation: MSConversation?

    /// The message this instance was invoked for, if any.
    ///
    /// For a transcript presentation this is the message being rendered. For your own
    /// interface it's the message the user tapped, or `nil` if they opened the app directly.
    ///
    /// Driven by the documented `didBecomeActive`/`didSelectMessage` callbacks. Note that
    /// `MSConversation.selectedMessage` makes no KVO guarantee, so observing it that way
    /// relies on undocumented behaviour.
    @Published public private(set) var selectedMessage: MSMessage?

    /// Whether the extension is currently active.
    @Published public private(set) var isActive: Bool = false

    /// The host controller, for anything this session doesn't wrap.
    public weak var host: MSMessagesAppViewController?

    private var arbiter: PresentationStyleArbiter
    private var observers: [WeakObserver] = []

    init(host: MSMessagesAppViewController) {
        self.host = host
        self.presentationStyle = host.presentationStyle
        self.presentationContext = host.presentationContext
        self.arbiter = PresentationStyleArbiter(current: host.presentationStyle)
        self.userPreferredStyle = arbiter.userPreferred
        self.role = MessagesInstanceRole.resolve(
            presentationStyle: host.presentationStyle,
            isMessagePending: host.activeConversation?.selectedMessage?.isPending
        )
        self.conversation = host.activeConversation
        self.selectedMessage = host.activeConversation?.selectedMessage
    }

    // MARK: - Participants

    /// This device's identifier within the conversation.
    ///
    /// - Important: Not portable identity. Messages documents these UUIDs as "scoped to this
    ///   device", changing if the extension is disabled and re-enabled or the containing app
    ///   is reinstalled, and `MSMessage.senderParticipantIdentifier` "will be different on
    ///   all devices that participate in the conversation". Two participants therefore see
    ///   different UUIDs for the same person. Use them to tell participants apart *within one
    ///   device's view of a conversation*, and never as a key you put in a message payload.
    public var localParticipantIdentifier: UUID? {
        currentConversation?.localParticipantIdentifier
    }

    /// Identifiers of the other participants. Carries the same caveats as
    /// ``localParticipantIdentifier``.
    public var remoteParticipantIdentifiers: [UUID] {
        currentConversation?.remoteParticipantIdentifiers ?? []
    }

    /// Whether this is a one-to-one conversation rather than a group.
    ///
    /// `nil` until the extension has become active.
    public var isOneOnOne: Bool? {
        guard let count = currentConversation?.remoteParticipantIdentifiers.count else {
            return nil
        }
        return count == 1
    }

    private var currentConversation: MSConversation? {
        host?.activeConversation ?? conversation
    }

    // MARK: - Presentation

    /// Asks Messages to change presentation style.
    ///
    /// The request is recorded so the resulting transition isn't mistaken for the user
    /// resizing the sheet, which keeps ``userPreferredStyle`` accurate.
    ///
    /// - Note: From a transcript presentation this does not transition anything. Messages
    ///   documents that it instead instantiates a *new* controller in the requested style, so
    ///   nothing held in this session carries over to it. Put anything the new instance needs
    ///   in the message payload.
    public func requestPresentationStyle(_ style: RequestablePresentationStyle) {
        arbiter.didRequest(style)
        host?.requestPresentationStyle(style.presentationStyle)
    }

    /// Returns the sheet to the size the user last chose for themselves.
    public func restoreUserPreferredStyle() {
        requestPresentationStyle(userPreferredStyle)
    }

    /// Dismisses the extension and brings back the keyboard.
    ///
    /// - Note: Documented as doing nothing when the presentation style is `.transcript`, so
    ///   it is a no-op for any role other than ``MessagesInstanceRole/app``.
    public func dismiss() {
        host?.dismiss()
    }

    // MARK: - Staging and sending

    // `insert` puts the message in the input field for the user to send by hand; `send`
    // transmits it directly. They are not interchangeable — see the doc comments.

    /// Stages a message in the input field for the user to send.
    ///
    /// Replaces whatever was already staged. The user still has to tap send.
    public func insert(_ message: MSMessage) async throws {
        try await perform { $0.insert(message, completionHandler: $1) }
    }

    /// Stages text in the input field. See ``insert(_:)``.
    public func insert(text: String) async throws {
        try await perform { $0.insertText(text, completionHandler: $1) }
    }

    /// Stages a sticker in the input field. See ``insert(_:)``.
    public func insert(sticker: MSSticker) async throws {
        try await perform { $0.insert(sticker, completionHandler: $1) }
    }

    /// Stages a file attachment in the input field. See ``insert(_:)``.
    ///
    /// - Parameters:
    ///   - attachment: A file URL.
    ///   - filename: A more readable name to show instead of the URL's own.
    public func insert(attachment: URL, filename: String? = nil) async throws {
        try await perform {
            $0.insertAttachment(attachment, withAlternateFilename: filename, completionHandler: $1)
        }
    }

    /// Sends a message immediately, without the user tapping send.
    ///
    /// - Important: Messages requires that "the app must be visible and have had a recent
    ///   touch interaction since either last launch or last send". Calling this from a timer,
    ///   or straight out of an activation callback, throws
    ///   ``MessagesSessionError/sendWithoutRecentInteraction`` or
    ///   ``MessagesSessionError/sendWhileNotVisible``. If a send isn't the direct result of
    ///   the user tapping something, stage it with ``insert(_:)`` instead.
    public func send(_ message: MSMessage) async throws {
        try await perform { $0.send(message, completionHandler: $1) }
    }

    /// Sends text immediately. Carries the same requirements as ``send(_:)``.
    public func send(text: String) async throws {
        try await perform { $0.sendText(text, completionHandler: $1) }
    }

    /// Sends a sticker immediately. Carries the same requirements as ``send(_:)``.
    public func send(sticker: MSSticker) async throws {
        try await perform { $0.send(sticker, completionHandler: $1) }
    }

    /// Sends a file attachment immediately. Carries the same requirements as ``send(_:)``.
    public func send(attachment: URL, filename: String? = nil) async throws {
        try await perform {
            $0.sendAttachment(attachment, withAlternateFilename: filename, completionHandler: $1)
        }
    }

    private func perform(
        _ body: (MSConversation, @escaping @Sendable (Error?) -> Void) -> Void
    ) async throws {
        // Pre-checked rather than left to the completion handler, so callers get a typed
        // error naming the actual problem instead of an opaque NSError code.
        if presentationContext == .media {
            throw MessagesSessionError.unavailableInPresentationContext(presentationContext)
        }
        guard let conversation = currentConversation else {
            throw MessagesSessionError.noActiveConversation
        }
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            body(conversation) { error in
                if let error {
                    continuation.resume(throwing: MessagesSessionError(error))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Observers

    /// Registers an observer, held weakly.
    ///
    /// Registering the same object twice has no effect.
    public func addObserver(_ observer: any MessagesActivityObserver) {
        register(observer)
    }

    /// Registers an observer, held weakly.
    public func addObserver(_ observer: any MessagesInteractionObserver) {
        register(observer)
    }

    /// Registers an observer that wants both halves of the lifecycle.
    ///
    /// Exists so a type conforming to both protocols doesn't make `addObserver` ambiguous.
    public func addObserver(
        _ observer: any MessagesActivityObserver & MessagesInteractionObserver
    ) {
        register(observer)
    }

    public func removeObserver(_ observer: AnyObject) {
        observers.removeAll { $0.object === observer || $0.object == nil }
    }

    private func register(_ observer: AnyObject) {
        observers.removeAll { $0.object == nil }
        guard !observers.contains(where: { $0.object === observer }) else { return }
        observers.append(WeakObserver(object: observer))
    }

    private var activityObservers: [any MessagesActivityObserver] {
        observers.compactMap { $0.object as? any MessagesActivityObserver }
    }

    private var interactionObservers: [any MessagesInteractionObserver] {
        observers.compactMap { $0.object as? any MessagesInteractionObserver }
    }

    // MARK: - Host callbacks

    // Called by `MessagesAppHost`. Each updates published state, then fans out to observers.

    func hostWillBecomeActive(with conversation: MSConversation) {
        self.conversation = conversation
        refreshDerivedState(selectedMessage: conversation.selectedMessage)
        activityObservers.forEach { $0.willBecomeActive(with: conversation) }
    }

    func hostDidBecomeActive(with conversation: MSConversation) {
        self.conversation = conversation
        self.isActive = true
        refreshDerivedState(selectedMessage: conversation.selectedMessage)
        activityObservers.forEach { $0.didBecomeActive(with: conversation) }
    }

    func hostWillResignActive(with conversation: MSConversation) {
        activityObservers.forEach { $0.willResignActive(with: conversation) }
    }

    func hostDidResignActive(with conversation: MSConversation) {
        self.isActive = false
        activityObservers.forEach { $0.didResignActive(with: conversation) }
    }

    func hostWillSelect(_ message: MSMessage, in conversation: MSConversation) {
        interactionObservers.forEach { $0.willSelect(message, in: conversation) }
    }

    func hostDidSelect(_ message: MSMessage, in conversation: MSConversation) {
        self.conversation = conversation
        refreshDerivedState(selectedMessage: message)
        interactionObservers.forEach { $0.didSelect(message, in: conversation) }
    }

    func hostDidReceive(_ message: MSMessage, in conversation: MSConversation) {
        interactionObservers.forEach { $0.didReceive(message, in: conversation) }
    }

    func hostDidStartSending(_ message: MSMessage, in conversation: MSConversation) {
        // The staged message is on its way, so it is no longer pending and the role may have
        // shifted out of `.inputFieldPreview`.
        refreshDerivedState(selectedMessage: selectedMessage)
        interactionObservers.forEach { $0.didStartSending(message, in: conversation) }
    }

    func hostDidCancelSending(_ message: MSMessage, in conversation: MSConversation) {
        refreshDerivedState(selectedMessage: conversation.selectedMessage)
        interactionObservers.forEach { $0.didCancelSending(message, in: conversation) }
    }

    func hostWillTransition(to style: MSMessagesAppPresentationStyle) {
        arbiter.willTransition(to: style)
        publishArbiterState()
        refreshDerivedState(selectedMessage: selectedMessage)
        interactionObservers.forEach { $0.willTransition(to: style) }
    }

    func hostDidTransition(to style: MSMessagesAppPresentationStyle) {
        arbiter.didTransition(to: style)
        publishArbiterState()
        refreshDerivedState(selectedMessage: selectedMessage)
        interactionObservers.forEach { $0.didTransition(to: style) }
    }

    private func publishArbiterState() {
        presentationStyle = arbiter.current
        userPreferredStyle = arbiter.userPreferred
    }

    private func refreshDerivedState(selectedMessage message: MSMessage?) {
        selectedMessage = message
        presentationContext = host?.presentationContext ?? presentationContext
        role = MessagesInstanceRole.resolve(
            presentationStyle: presentationStyle,
            isMessagePending: message?.isPending
        )
    }
}

/// Weak box so registering an observer doesn't keep it alive.
private struct WeakObserver {
    weak var object: AnyObject?
}
