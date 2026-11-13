import Foundation
import Messages

/// Why staging or sending failed.
///
/// The interesting failure modes here are ones Messages reports as opaque `NSError` codes
/// in `MSMessagesErrorDomain`. They're lifted into cases because each one means something
/// specific that a caller can act on, and because two of them enforce a `send` requirement
/// that is documented only in prose.
public enum MessagesSessionError: Error, Equatable {
    /// The host had no `activeConversation`, so there was nothing to stage into.
    case noActiveConversation

    /// Staging and sending are unavailable in this presentation context.
    ///
    /// Every `insert`/`send` method on `MSConversation` fails when the extension was
    /// launched over media rather than in Messages. Checked before calling through, so this
    /// arrives instead of a completion-handler error.
    case unavailableInPresentationContext(MSMessagesAppPresentationContext)

    /// The message's `url` was too large to transmit.
    ///
    /// The whole payload for a custom message rides in that URL, so this is the ceiling on
    /// how much state a message can carry. Messages defines the error but not the limit.
    case urlExceedsMaxSize

    /// `send` was called without a recent user interaction.
    ///
    /// `sendMessage(_:completionHandler:)` requires that "the app must be visible and have
    /// had a recent touch interaction since either last launch or last send". Sending from
    /// a timer, a notification, or straight out of `didBecomeActive` trips this.
    case sendWithoutRecentInteraction

    /// `send` was called while the extension wasn't visible. See
    /// ``sendWithoutRecentInteraction``.
    case sendWhileNotVisible

    /// A recognized `MSMessagesErrorDomain` failure with no dedicated case above.
    case messages(code: Int, description: String)

    /// A failure from outside `MSMessagesErrorDomain`.
    case other(description: String)

    init(_ error: Error) {
        let nsError = error as NSError
        guard nsError.domain == MSMessagesErrorDomain else {
            self = .other(description: nsError.localizedDescription)
            return
        }

        switch MSMessageErrorCode(rawValue: nsError.code) {
        case .urlExceedsMaxSize:
            self = .urlExceedsMaxSize
        case .sendWithoutRecentInteraction:
            self = .sendWithoutRecentInteraction
        case .sendWhileNotVisible:
            self = .sendWhileNotVisible
        case .apiUnavailableInPresentationContext:
            // Reachable if the context changed between the pre-check and the callback.
            self = .unavailableInPresentationContext(.media)
        default:
            self = .messages(code: nsError.code, description: nsError.localizedDescription)
        }
    }
}
