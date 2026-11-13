import Messages

/// Tracks which presentation style the *user* chose, as distinct from one the extension
/// asked for.
///
/// Messages gives you no way to tell these apart: `willTransition(to:)` fires identically
/// whether the user dragged the sheet or you called `requestPresentationStyle(_:)`. Keeping
/// the two separate is what lets you expand for a task and then put the sheet back the way
/// the user had it — see ``MessagesSession/restoreUserPreferredStyle()``.
///
/// Deliberately a value type with no reference to the host controller, so every rule below
/// is testable without a simulator.
///
/// Only meaningful for ``MessagesInstanceRole/app`` instances. Transcript presentations
/// never receive transition callbacks at all, so an arbiter belonging to one stays at its
/// initial value forever.
struct PresentationStyleArbiter: Equatable {
    /// The style currently showing.
    private(set) var current: MSMessagesAppPresentationStyle

    /// The last style the user picked for themselves.
    ///
    /// Typed as ``RequestablePresentationStyle``, so a transcript presentation cannot be
    /// recorded here and later "restored" into nonsense.
    private(set) var userPreferred: RequestablePresentationStyle

    /// A style this extension asked for that no transition has confirmed yet.
    private var pending: RequestablePresentationStyle?

    init(current: MSMessagesAppPresentationStyle) {
        self.current = current
        self.userPreferred = RequestablePresentationStyle(current) ?? .compact
    }

    mutating func didRequest(_ style: RequestablePresentationStyle) {
        pending = style
    }

    mutating func willTransition(to style: MSMessagesAppPresentationStyle) {
        let requestable = RequestablePresentationStyle(style)

        // Compare the pending *value* rather than trusting a bare "we asked for something"
        // flag. Requesting a style the system declines to honour — notably the style
        // already showing — produces no transition callback at all, so a boolean latch
        // would stay armed and silently swallow the next genuine user resize.
        let isProgrammatic = pending != nil && pending == requestable
        pending = nil

        if !isProgrammatic, let requestable {
            userPreferred = requestable
        }
        current = style
    }

    mutating func didTransition(to style: MSMessagesAppPresentationStyle) {
        current = style
        // If a request did land but on some other style, the pending value is stale now
        // regardless. Clearing here as well as in `willTransition` keeps the two callbacks
        // independently safe to miss.
        pending = nil
    }
}
