import Messages
import UIKit

/// The bubble shown for a message on devices that can't run your extension.
///
/// A live layout needs one of these, and `MSMessageLiveLayout` already refuses to be built
/// without it. What it can't stop you doing is passing an *empty* `MSMessageTemplateLayout` —
/// every property on that class is optional, so a blank one compiles and quietly ships an empty
/// bubble to anyone on macOS, SMS, or without your app installed.
///
/// This type requires at least an image or a caption, so that bubble always says something.
public struct AlternateLayout {
    private var image: UIImage?
    private var imageTitle: String?
    private var imageSubtitle: String?
    private var caption: String?
    private var subcaption: String?
    private var trailingCaption: String?
    private var trailingSubcaption: String?

    /// An image-led bubble.
    public init(
        image: UIImage,
        imageTitle: String? = nil,
        imageSubtitle: String? = nil,
        caption: String? = nil,
        subcaption: String? = nil,
        trailingCaption: String? = nil,
        trailingSubcaption: String? = nil
    ) {
        self.image = image
        self.imageTitle = imageTitle
        self.imageSubtitle = imageSubtitle
        self.caption = caption
        self.subcaption = subcaption
        self.trailingCaption = trailingCaption
        self.trailingSubcaption = trailingSubcaption
    }

    /// A text-only bubble.
    public init(
        caption: String,
        subcaption: String? = nil,
        trailingCaption: String? = nil,
        trailingSubcaption: String? = nil
    ) {
        self.caption = caption
        self.subcaption = subcaption
        self.trailingCaption = trailingCaption
        self.trailingSubcaption = trailingSubcaption
    }

    public func makeTemplateLayout() -> MSMessageTemplateLayout {
        let layout = MSMessageTemplateLayout()
        layout.image = image
        layout.imageTitle = imageTitle
        layout.imageSubtitle = imageSubtitle
        layout.caption = caption
        layout.subcaption = subcaption
        layout.trailingCaption = trailingCaption
        layout.trailingSubcaption = trailingSubcaption
        return layout
    }
}

/// How a message should be drawn in the transcript.
public enum MessageLayout {
    /// A static bubble Messages renders itself.
    case template(MSMessageTemplateLayout)

    /// A bubble your extension renders, by running in a transcript presentation.
    ///
    /// - Parameter alternate: What to show where your extension can't run. See
    ///   ``AlternateLayout``.
    case live(alternate: AlternateLayout)

    func makeMessageLayout() -> MSMessageLayout {
        switch self {
        case .template(let layout):
            layout
        case .live(let alternate):
            MSMessageLiveLayout(alternateLayout: alternate.makeTemplateLayout())
        }
    }
}
