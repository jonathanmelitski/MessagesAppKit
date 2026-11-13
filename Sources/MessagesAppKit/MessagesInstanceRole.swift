import Messages

/// Which of your extension's concurrently-running instances this one is.
///
/// A Messages extension does not run one view controller at a time. Apple documents that
/// "your app may have multiple instances of its `MSMessagesAppViewController` subclass
/// running concurrently": one for every live-layout message visible in the transcript, one
/// for a message staged in the input field, and one for the app's own interface. They
/// share a process, so they must not share state — see ``MessagesSession`` for the rule
/// this package follows.
///
/// Read it from the environment with `@Environment(\.messagesInstanceRole)` to tell a
/// preview of your own unsent message apart from a bubble that has actually been sent.
public enum MessagesInstanceRole: Hashable, Sendable {
    /// Your extension's own interface, presented `.compact` or `.expanded`.
    case app

    /// A live-layout bubble for a message that has been sent or received.
    case transcriptBubble

    /// A live-layout bubble for a message staged in the input field but not yet sent.
    ///
    /// Reached by calling ``MessagesSession/insert(_:)``, which stages a message for the
    /// user to send by hand.
    case inputFieldPreview

    /// Derives the role from the two documented signals that distinguish the instances.
    ///
    /// Takes `isMessagePending` rather than an `MSMessage` because `MSMessage.pending` is
    /// read-only and can't be faked, which would make this untestable.
    static func resolve(
        presentationStyle: MSMessagesAppPresentationStyle,
        isMessagePending: Bool?
    ) -> MessagesInstanceRole {
        guard presentationStyle == .transcript else { return .app }
        // A live layout always arrives with a selected message. Treat an absent one as a
        // committed bubble, matching `isPending`'s own default of `false`.
        return isMessagePending == true ? .inputFieldPreview : .transcriptBubble
    }
}
