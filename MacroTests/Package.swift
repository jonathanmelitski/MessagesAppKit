// swift-tools-version: 6.0

import CompilerPluginSupport
import PackageDescription

// A harness that exists only to run the macro's expansion tests. It is never published and nothing
// depends on it.
//
// It has to be a separate package because `swift test` in MessagesAppKit builds *every* target in
// that package, including the two iOS-only libraries, which fail on `import Messages` when SwiftPM
// builds them for the host. Declaring the test target over there makes it permanently unrunnable.
// `xcodebuild test` is not an alternative either: Xcode compiles a package's macro target for the
// test destination while pointing at prebuilt macOS swift-syntax modules, which fails with
// `SDK does not match` unless you set the global `IDEPackageEnablePrebuilts` user default.
//
// `Sources/MessagesAppKitMacros` is a symlink to `../Sources/MessagesAppKitMacros`, so there is one
// copy of the macro sources. The alternatives were both worse: a target `path:` of `../Sources/...`
// is rejected outright ("outside the package root"), and a `.package(path: "..")` dependency would
// force MessagesAppKit to export its macro as a public product consumers should never use.
let package = Package(
    name: "MacroTests",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
    ],
    targets: [
        .macro(
            name: "MessagesAppKitMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ],
            path: "Sources/MessagesAppKitMacros"
        ),
        .testTarget(
            name: "MessagesAppKitMacrosTests",
            dependencies: [
                "MessagesAppKitMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ],
            path: "Tests/MessagesAppKitMacrosTests"
        ),
    ]
)
