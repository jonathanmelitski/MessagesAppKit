import Messages

/// A presentation style the extension is allowed to ask Messages for.
///
/// `MSMessagesAppPresentationStyle` has three cases, but `requestPresentationStyle(_:)`
/// documents that `.transcript` "is not a valid presentation style to request". This type
/// omits it so that mistake can't be written down.
///
/// It doubles as the type of ``MessagesSession/userPreferredStyle``, which means a
/// transcript presentation can't be mistaken for a size the user chose.
public enum RequestablePresentationStyle: Hashable, Sendable, CaseIterable {
    case compact
    case expanded

    /// Narrows a framework style, returning `nil` for `.transcript`.
    public init?(_ style: MSMessagesAppPresentationStyle) {
        switch style {
        case .compact: self = .compact
        case .expanded: self = .expanded
        case .transcript: return nil
        @unknown default: return nil
        }
    }

    public var presentationStyle: MSMessagesAppPresentationStyle {
        switch self {
        case .compact: .compact
        case .expanded: .expanded
        }
    }
}
