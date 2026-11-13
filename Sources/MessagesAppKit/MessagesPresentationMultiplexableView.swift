import Messages
import SwiftUI

/// A view that renders differently depending on how Messages is presenting it.
///
/// Messages shows your extension in three quite different frames: a keyboard-sized strip, a
/// near-fullscreen sheet, and a bubble inside the transcript. Rather than branching inside one
/// `body`, declare the three bodies separately and let the default `body` pick:
///
/// ```swift
/// struct WorkoutScreen: MessagesPresentationMultiplexableView {
///     var compact: some View { WorkoutStrip() }
///     var expanded: some View { WorkoutDetail() }
///     var transcript: some View { WorkoutBubble() }
/// }
/// ```
///
/// The style comes from the environment, so conforming views take no `style` parameter and
/// parents don't thread one down.
///
/// If two or three presentations should look the same, implement only ``compact`` and the rest
/// fall back to it.
///
/// - Important: ``transcript`` may be rendering in many instances at once — Messages runs one
///   controller per visible live-layout bubble. Keep it cheap and free of side effects, and
///   don't `fatalError()` in it on the assumption it's unreachable.
public protocol MessagesPresentationMultiplexableView: View {
    associatedtype CompactBody: View
    associatedtype ExpandedBody: View
    associatedtype TranscriptBody: View

    /// Shown when Messages presents the extension at keyboard height.
    @ViewBuilder var compact: CompactBody { get }

    /// Shown when Messages presents the extension as a near-fullscreen sheet.
    @ViewBuilder var expanded: ExpandedBody { get }

    /// Shown inside a message bubble in the transcript.
    @ViewBuilder var transcript: TranscriptBody { get }
}

public extension MessagesPresentationMultiplexableView {
    var body: some View {
        _StyleMultiplexer(content: self)
    }
}

// Fallbacks, so a view whose presentations don't differ implements one body instead of three.
// Swift infers `ExpandedBody`/`TranscriptBody` as `CompactBody` when the corresponding
// property isn't declared, which selects these.

public extension MessagesPresentationMultiplexableView where ExpandedBody == CompactBody {
    var expanded: CompactBody { compact }
}

public extension MessagesPresentationMultiplexableView where TranscriptBody == CompactBody {
    var transcript: CompactBody { compact }
}

/// Picks one of a ``MessagesPresentationMultiplexableView``'s three bodies.
///
/// Holds the view rather than its three bodies so that only the selected one is ever built.
public struct _StyleMultiplexer<Content: MessagesPresentationMultiplexableView>: View {
    @Environment(\.messagesPresentationStyle) private var style

    private let content: Content

    public init(content: Content) {
        self.content = content
    }

    public var body: some View {
        switch style {
        case .compact: content.compact
        case .expanded: content.expanded
        case .transcript: content.transcript
        @unknown default: EmptyView()
        }
    }
}
