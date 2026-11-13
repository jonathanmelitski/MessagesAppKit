import Messages

// The lifecycle is split into two protocols because Messages itself splits it. Four
// activation methods live on `MSMessagesAppViewController`; the other seven live in its
// `CompactOrExpandedPresentation` category, each documented as "will not be called when the
// `presentationStyle` is `Transcript` or the `presentationContext` is `Media`". Flattening
// them into one protocol would hide the fact that most of them never fire in a transcript
// bubble.
//
// Every method has a no-op default, so conforming types implement only what they need.

/// Activation callbacks. Delivered to every instance regardless of role.
@MainActor
public protocol MessagesActivityObserver: AnyObject {
    func willBecomeActive(with conversation: MSConversation)
    func didBecomeActive(with conversation: MSConversation)
    func willResignActive(with conversation: MSConversation)
    func didResignActive(with conversation: MSConversation)
}

public extension MessagesActivityObserver {
    func willBecomeActive(with conversation: MSConversation) {}
    func didBecomeActive(with conversation: MSConversation) {}
    func willResignActive(with conversation: MSConversation) {}
    func didResignActive(with conversation: MSConversation) {}
}

/// Selection, delivery, and presentation-transition callbacks.
///
/// - Important: None of these are delivered when ``MessagesSession/role`` is
///   ``MessagesInstanceRole/transcriptBubble`` or ``MessagesInstanceRole/inputFieldPreview``,
///   or when the extension was launched over media. Messages simply never calls them on a
///   transcript presentation. If you need to react to something in a transcript bubble, the
///   information has to come from the message payload instead.
@MainActor
public protocol MessagesInteractionObserver: AnyObject {
    func willSelect(_ message: MSMessage, in conversation: MSConversation)
    func didSelect(_ message: MSMessage, in conversation: MSConversation)
    func didReceive(_ message: MSMessage, in conversation: MSConversation)
    func didStartSending(_ message: MSMessage, in conversation: MSConversation)
    func didCancelSending(_ message: MSMessage, in conversation: MSConversation)
    func willTransition(to style: MSMessagesAppPresentationStyle)
    func didTransition(to style: MSMessagesAppPresentationStyle)
}

public extension MessagesInteractionObserver {
    func willSelect(_ message: MSMessage, in conversation: MSConversation) {}
    func didSelect(_ message: MSMessage, in conversation: MSConversation) {}
    func didReceive(_ message: MSMessage, in conversation: MSConversation) {}
    func didStartSending(_ message: MSMessage, in conversation: MSConversation) {}
    func didCancelSending(_ message: MSMessage, in conversation: MSConversation) {}
    func willTransition(to style: MSMessagesAppPresentationStyle) {}
    func didTransition(to style: MSMessagesAppPresentationStyle) {}
}
