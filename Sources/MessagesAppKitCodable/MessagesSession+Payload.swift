import Foundation
import Messages
import MessagesAppKit

public extension MessagesSession {

    /// Decodes the payload of the message this instance was invoked for.
    ///
    /// For a transcript presentation that's the message being rendered; for your own interface
    /// it's the message the user tapped.
    ///
    /// Returns `nil` when there is no selected message at all — the user opened your app rather
    /// than tapping a bubble. Throws when a message *is* selected but its payload can't be read,
    /// so a mismatched or corrupt payload doesn't silently look like "no message".
    func payload<Payload: MessagePayload>(_ type: Payload.Type) throws -> Payload? {
        guard let message = selectedMessage else { return nil }
        guard let url = message.url else { throw MessagePayloadError.noPayload }
        return try PayloadCodec.decode(type, from: url)
    }

    /// Builds a message carrying `payload`, ready to hand to `insert` or `send`.
    ///
    /// Returns the message rather than sending it, so the choice between staging
    /// (``MessagesSession/insert(_:)``) and sending outright (``MessagesSession/send(_:)``) stays
    /// in one place instead of being duplicated per payload type.
    ///
    /// - Parameters:
    ///   - payload: The value to encode into the message URL.
    ///   - summaryText: Shown by Messages where a bubble can't be drawn — notification
    ///     previews, the conversation list.
    ///   - accessibilityLabel: Spoken description of the message. Worth passing for a
    ///     ``MessageLayout/live(alternate:)`` message: you draw that bubble yourself, so it has
    ///     no accessible content unless you supply this.
    ///   - layout: How the bubble should look.
    ///   - continuingSelectedSession: Whether this message updates the selected message's
    ///     conversation thread rather than starting a new one.
    ///
    ///     This is the difference between "I added scoops to *our* sundae" and "here's a new
    ///     sundae". `MSSession` is what ties them together: a message created with an existing
    ///     session replaces that message in place and moves it to the bottom of the transcript,
    ///     while a fresh session starts a separate bubble.
    ///
    ///     Pass `true` when the user is acting on the message they opened — completing it,
    ///     voting on it, adding to it. Pass `false` when they're creating something new. There's
    ///     no sensible default and getting it wrong fails silently, which is why it isn't
    ///     defaulted.
    ///
    ///     Falls back to a new session if `true` but nothing is selected.
    func makeMessage<Payload: MessagePayload>(
        _ payload: Payload,
        summaryText: String?,
        accessibilityLabel: String? = nil,
        layout: MessageLayout,
        continuingSelectedSession: Bool
    ) throws -> MSMessage {
        let session = continuingSelectedSession
            ? (selectedMessage?.session ?? MSSession())
            : MSSession()

        let message = MSMessage(session: session)
        message.url = try PayloadCodec.encodeToURL(payload)
        message.layout = layout.makeMessageLayout()
        message.summaryText = summaryText
        message.accessibilityLabel = accessibilityLabel
        return message
    }
}
