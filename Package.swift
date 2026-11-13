// swift-tools-version: 6.0

import CompilerPluginSupport
import PackageDescription

// Platform support is declared here and nowhere else — no source file repeats it with
// `#if os(iOS)`.
//
// Messages.framework ships in exactly two SDKs: iOS, and macOS's `System/iOSSupport`, which is
// Mac Catalyst. There is no native macOS, visionOS, tvOS, or watchOS build of it, so the two
// libraries are iOS and Mac Catalyst only.
//
// `.macOS` is here for one target: `MessagesAppKitMacros`. A compiler plugin is a host tool, so
// it builds for macOS even when the code using it builds for iOS, and SwiftPM takes the plugin's
// deployment target from this list — defaulting to macOS 10.13, below swift-syntax's 10.15 floor,
// which fails every build including the iOS one. So read this list as "the union across targets",
// not as a claim that MessagesAppKit runs on macOS. `platforms:` has no per-target form, and
// splitting the macro into its own package is not an option: SwiftPM rejects a path dependency in
// any package consumed by URL, which would make this one impossible to distribute.
//
// Practical consequence: `swift build` and `swift test` here fail on `import Messages`, because
// SwiftPM always builds for the host. Build with an iOS or Catalyst destination, and run the macro
// tests from the MacroTests harness package. See README.
//
// The iOS 16 floor is deliberate: every Messages API this package touches is available at or below
// iOS 12 (`.transcript` and `send*` are iOS 11, `presentationContext` and `MSMessage.isPending`
// are iOS 11-12), so nothing in here needs `@available` gating either.
let package = Package(
    name: "MessagesAppKit",
    platforms: [.iOS(.v16), .macCatalyst(.v16), .macOS(.v13)],
    products: [
        .library(
            name: "MessagesAppKit",
            targets: ["MessagesAppKit"]
        ),
        .library(
            name: "MessagesAppKitCodable",
            targets: ["MessagesAppKitCodable"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
    ],
    targets: [
        .target(
            name: "MessagesAppKit",
            dependencies: ["MessagesAppKitMacros"]
        ),
        .macro(
            name: "MessagesAppKitMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "MessagesAppKitCodable",
            dependencies: ["MessagesAppKit"]
        ),
    ]
)
