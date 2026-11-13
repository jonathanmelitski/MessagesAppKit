# MessagesAppKit

Write iMessage app extensions in SwiftUI.

Messages extensions are a UIKit API from 2016. `MSMessagesAppViewController` wants you to
swap child view controllers on presentation changes, hand-decode message payloads out of
URLs, and implement a twelve-method lifecycle where most methods silently never fire. This
package puts a SwiftUI shape over it without hiding any of it.

```swift
import MessagesAppKit
import SwiftUI

@MessagesApp
struct MyMessagesApp {
    var body: some View { HomeScreen() }
}
```

That's the whole entry point. No `Info.plist` edit — the macro generates the
`MessagesViewController` class Xcode's template already names as
`NSExtensionPrincipalClass`.

Requires iOS 16 or Mac Catalyst 16. There is no `@available` gating anywhere in the
package, and no `#if os(iOS)` either — the floor is set where every Messages API used is
unconditionally available, and platform support is stated once in `Package.swift`.

## Progressive disclosure

Five rungs. Each is sugar over the one below, and nothing on the way down is `final` or
private — you can stop at any level and reach through to the one underneath.

| | | |
|---|---|---|
| **L0** | `@MessagesApp` | two declarations, no plist edit |
| **L1** | `@EnvironmentObject var session: MessagesSession` | style, role, selected message, staging and sending |
| **L2** | `MessagesPresentationMultiplexableView` | a body per presentation style |
| **L3** | observer protocols, raw `MSConversation`/`MSMessage`, `transcriptContentSize` |  |
| **L4** | subclass `MessagesAppHost` | override any `MSMessagesAppViewController` method |

### L0 — bind a view

`@MessagesApp` is pure sugar. It expands to exactly this, which you can write yourself if
you want a different principal class name or somewhere to put overrides:

```swift
@objc(MessagesViewController)
final class MessagesViewController: MessagesAppHost<MyRootView> {}
```

The host builds your root view with `MyRootView()`, which is what `MessagesRootView`'s
`init()` requirement is for. If your root needs arguments, override `makeRootView()`.

### L1 — the session

```swift
struct HomeScreen: View {
    @EnvironmentObject private var session: MessagesSession

    var body: some View {
        Button("Send") {
            Task { try await session.insert(message) }
        }
    }
}
```

`insert` stages a message in the input field for the user to send. `send` transmits
immediately, but Messages requires the app be visible with a recent touch interaction —
call it from a timer or an activation callback and you get
`.sendWithoutRecentInteraction` or `.sendWhileNotVisible`. All eight staging and sending
methods are wrapped `async throws`, with `MSMessagesErrorDomain` codes lifted into typed
cases.

### L2 — one body per presentation

Messages shows your extension in three quite different frames. Declare them separately
instead of branching:

```swift
struct WorkoutScreen: MessagesPresentationMultiplexableView {
    var compact: some View { WorkoutStrip() }
    var expanded: some View { WorkoutDetail() }
    var transcript: some View { WorkoutBubble() }
}
```

The style comes from the environment, so conforming views take no `style` parameter and
parents don't thread one down. Implement only `compact` and the other two fall back to it.

Previews work by setting the environment value:

```swift
#Preview {
    WorkoutScreen().environment(\.messagesPresentationStyle, .expanded)
}
```

### L3 — lifecycle

Two protocols, because Messages splits its own lifecycle in two. Every method has a no-op
default, so implement only what you want:

```swift
final class Coordinator: MessagesActivityObserver, MessagesInteractionObserver {
    func didBecomeActive(with conversation: MSConversation) { ... }
    func didReceive(_ message: MSMessage, in conversation: MSConversation) { ... }
}

session.addObserver(coordinator)  // held weakly
```

`MessagesActivityObserver` always fires. `MessagesInteractionObserver` never fires in a
transcript presentation or over media — see invariant 3 below.

For anything not wrapped, `session.host` is the controller itself.

### L4 — the host

```swift
final class MessagesViewController: MessagesAppHost<MyRootView> {
    override var transcriptContentSize: CGSize? { CGSize(width: 300, height: 250) }
    override var hostBackgroundColor: UIColor? { .black }

    override func didBecomeActive(with conversation: MSConversation) {
        super.didBecomeActive(with: conversation)   // keeps the session in sync
        ...
    }
}
```

## MessagesAppKitCodable

Opt-in, because it's an opinion about encoding rather than part of hosting SwiftUI.

```swift
import MessagesAppKitCodable

struct Challenge: MessagePayload {
    var name: String
    var deadline: Date
}

// reading the message this instance was invoked for
let challenge = try session.payload(Challenge.self)

// writing
let message = try session.makeMessage(
    challenge,
    summaryText: "A challenge",
    accessibilityLabel: "Run four miles by 6pm",
    layout: .live(alternate: AlternateLayout(caption: "A challenge")),
    continuingSelectedSession: false
)
try await session.insert(message)
```

Two parameters worth understanding:

`continuingSelectedSession` isn't defaulted because both answers are right for different
actions and the wrong one fails silently. `MSSession` is what makes a message *update in
place* — pass `true` when the user is acting on the message they opened (completing it,
voting, adding to it) and the bubble is replaced; pass `false` when they're creating
something new and a separate bubble appears.

`AlternateLayout` requires an image or a caption. `MSMessageLiveLayout` already forces you
to supply a fallback layout, but every property on `MSMessageTemplateLayout` is optional,
so an empty one compiles and ships a blank bubble to anyone on macOS, SMS, or without your
app installed.

## Messages invariants worth knowing

These shaped the API, and they're the things that cost time to discover. Quotes are from
the iOS 26 SDK headers and Apple's `MSMessageLiveLayout` documentation.

**1. Your extension runs many times over, concurrently, in one process.** *"Your app may
have multiple instances of its `MSMessagesAppViewController` subclass running
concurrently"* — one per live-layout bubble visible in the transcript, one for a message
staged in the input field, and one for your own interface.

This package holds no `static` mutable state and gives every host instance its own
`MessagesSession`. Your code needs the same discipline: a shared in-memory store gets read
and written by every instance at once and goes stale immediately. Apple's `IceCreamBuilder`
sample re-reads `UserDefaults` on *every* access for exactly this reason, and its one
singleton holds only idempotent derived files.

**2. You can tell the instances apart.** `MSMessage.pending` is *"useful for knowing if the
`selectedMessage` of `activeConversation` represents an unsent message"*, which separates
the input-field instance from a real transcript bubble. Exposed as
`MessagesInstanceRole` — `.app`, `.transcriptBubble`, `.inputFieldPreview` — on the session
and in the environment.

**3. Half the lifecycle never fires in a transcript.** Four activation methods live on
`MSMessagesAppViewController`; the other seven live in a `CompactOrExpandedPresentation`
category, each documented *"will not be called when the `presentationStyle` is `Transcript`
or the `presentationContext` is `Media`"*. Hence two observer protocols rather than one.

**4. `.transcript` can't be requested.** *"`MSMessagesAppPresentationStyleTranscript` is not
a valid presentation style to request."* `requestPresentationStyle` therefore takes
`RequestablePresentationStyle`, which has no such case.

**5. Requesting a style from a transcript creates a new instance.** *"When the current
`presentationStyle` is `Transcript`, a new instance of `MSMessagesAppViewController` will be
instantiated with the requested presentation style if needed."* Nothing in the old
instance's session carries over, so anything the new one needs belongs in the message
payload. It also means transition callbacks never arrive in a transcript, which is why
`userPreferredStyle` is meaningless there.

**6. `MSConversation.selectedMessage` makes no KVO guarantee.** It's a plain `readonly`
property; observing it with `publisher(for:)` relies on undocumented behaviour. This
package tracks the selected message through `didBecomeActive` and `didSelectMessage`
instead, both available since iOS 10.

**7. `contentSizeThatFits(_:)` sizes the transcript bubble, nothing else.** *"This method
will only be called if the `presentationStyle` is `Transcript`."* Hence
`transcriptContentSize` rather than a name suggesting compact presentation.

**8. There are real error codes for the failures that matter.** `URLExceedsMaxSize`,
`SendWithoutRecentInteraction`, `SendWhileNotVisible`,
`APIUnavailableInPresentationContext`. All lifted into `MessagesSessionError`. Note there
*is* a size ceiling on the payload URL but Messages doesn't document the number.

**9. Participant UUIDs are not portable identity.** `localParticipantIdentifier` and
`remoteParticipantIdentifiers` are *"scoped to this device"* and change if the extension is
disabled and re-enabled or the containing app is reinstalled;
`MSMessage.senderParticipantIdentifier` *"will be different on all devices that participate
in the conversation"*. Two people see different UUIDs for the same person. Use them to tell
participants apart within one device's view of a conversation, never as a key inside a
message payload.

**10. Distinguishing a user resize from your own request takes bookkeeping.**
`willTransition(to:)` fires identically either way, so restoring the sheet to the size the
user chose means tracking which transitions you caused. `MessagesSession` does this;
`userPreferredStyle` and `restoreUserPreferredStyle()` are the result.

## Building and testing

```sh
xcodebuild -scheme MessagesAppKit -destination 'generic/platform=iOS' build
xcodebuild -scheme MessagesAppKit -destination 'platform=macOS,variant=Mac Catalyst' build
cd MacroTests && swift test          # macro expansion tests
```

`swift build` and `swift test` in the package root do **not** work, by design. SwiftPM always
builds for the host, and these libraries import `Messages`, which ships only in the iOS SDK
and in macOS's `System/iOSSupport` (Mac Catalyst) — there is no native macOS, visionOS, tvOS,
or watchOS build of it. Rather than paper over that with `#if os(iOS)` at the head of every
file, the constraint lives in `platforms:` and building for the wrong platform simply fails.

Two related wrinkles, both consequences of shipping a macro:

- **`platforms:` lists `.macOS(.v13)` anyway.** A compiler plugin is a host tool, so it builds
  for macOS even when your app builds for iOS, and SwiftPM takes the plugin's deployment target
  from that list — defaulting to macOS 10.13, below swift-syntax's 10.15 floor, which fails
  *every* build including the iOS one. Read the list as the union across targets, not as a
  claim that `MessagesAppKit` runs on macOS. `platforms:` has no per-target form, and moving
  the macro to its own package is not an option: SwiftPM rejects a path dependency inside any
  package consumed by URL, which would make this one impossible to distribute.
- **The macro tests live in `MacroTests/`.** `swift test` builds every target in a package, so
  a test target here would drag the iOS-only libraries into a host build and never run. And
  `xcodebuild test` is not an alternative: Xcode compiles the macro target for the *test*
  destination while pointing at prebuilt macOS swift-syntax modules, failing with
  `incompatible with this Swift compiler: SDK does not match` unless you set the global
  `IDEPackageEnablePrebuilts` user default. `MacroTests` is a tiny macOS-only harness whose
  `Sources/MessagesAppKitMacros` is a symlink to the real one, so there's a single copy.

Behaviour that needs a running extension — that the generated `@objc` class resolves as
`NSExtensionPrincipalClass`, and that concurrent transcript bubbles each get their own
session — is verified in a consumer app, not a test target.
