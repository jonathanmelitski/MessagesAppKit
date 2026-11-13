import Messages
import SwiftUI

private struct MessagesPresentationStyleKey: EnvironmentKey {
    static let defaultValue: MSMessagesAppPresentationStyle = .compact
}

private struct MessagesInstanceRoleKey: EnvironmentKey {
    static let defaultValue: MessagesInstanceRole = .app
}

public extension EnvironmentValues {
    /// The presentation style of the instance rendering this view.
    ///
    /// ``MessagesPresentationMultiplexableView`` reads this, which is why conforming views
    /// don't have to accept a style and thread it down to their children.
    ///
    /// Settable, so multiplexed views work in previews without a live extension:
    ///
    /// ```swift
    /// #Preview {
    ///     MyScreen().environment(\.messagesPresentationStyle, .expanded)
    /// }
    /// ```
    var messagesPresentationStyle: MSMessagesAppPresentationStyle {
        get { self[MessagesPresentationStyleKey.self] }
        set { self[MessagesPresentationStyleKey.self] = newValue }
    }

    /// Which of the concurrently-running extension instances is rendering this view.
    ///
    /// Mostly useful for telling a preview of the user's own unsent message apart from a
    /// bubble that has actually been sent. See ``MessagesInstanceRole``.
    var messagesInstanceRole: MessagesInstanceRole {
        get { self[MessagesInstanceRoleKey.self] }
        set { self[MessagesInstanceRoleKey.self] = newValue }
    }
}

/// Bridges a ``MessagesSession`` into the SwiftUI environment.
///
/// ``MessagesAppHost`` wraps your root view in one of these. It exists as a distinct view so
/// that observing the session re-publishes the style and role as environment values — which is
/// what removes the need to pass a presentation style through your view hierarchy by hand.
public struct MessagesRootContainer<Root: MessagesRootView>: View {
    @ObservedObject private var session: MessagesSession
    private let root: Root

    init(session: MessagesSession, root: Root) {
        self.session = session
        self.root = root
    }

    public var body: some View {
        root
            .environment(\.messagesPresentationStyle, session.presentationStyle)
            .environment(\.messagesInstanceRole, session.role)
            .environmentObject(session)
    }
}
