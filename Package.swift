// swift-tools-version:6.2

import Foundation
import PackageDescription

// `$ TEST_MAIN_ACTOR=1 swift test`
let usesMainActorInTest = ProcessInfo.processInfo.environment["TEST_MAIN_ACTOR"] == "1"

let package = Package(
    name: "Actomaton",
    // Xcode 16.4 / Swift 6.2
    platforms: [.macOS("15.4"), .iOS("18.4"), .watchOS("11.4"), .tvOS("18.4"), .visionOS("2.4")],
    products: [
        .library(
            name: "Actomaton",
            targets: ["Actomaton", "ActomatonDebugging"]
        ),
        .library(
            name: "ActomatonUI",
            targets: ["ActomatonUI", "ActomatonDebugging"]
        ),
        .library(
            name: "ActomatonCore",
            targets: ["ActomatonCore"]
        ),
        .library(
            name: "ActomatonEffect",
            targets: ["ActomatonEffect"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-case-paths", from: "0.7.0"),
        .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.0.0"),
        .package(url: "https://github.com/nicklockwood/SwiftFormat", from: "0.55.3"),
    ] + (
        usesMainActorInTest ? [
            .package(url: "https://github.com/pointfreeco/swift-concurrency-extras", from: "1.1.0")
        ] : []
    ),
    targets: [
        .target(
            name: "ActomatonCore",
            dependencies: []
        ),
        .target(
            name: "ActomatonEffect",
            dependencies: [
                "ActomatonCore",
            ]
        ),
        .target(
            name: "Actomaton",
            dependencies: [
                "ActomatonCore",
                "ActomatonEffect",
                .product(name: "CasePaths", package: "swift-case-paths"),
            ]
        ),
        .target(
            name: "ActomatonUI",
            dependencies: [
                "Actomaton", "ActomatonDebugging"
            ]
        ),
        .target(
            name: "ActomatonDebugging",
            dependencies: [
                "Actomaton",
                .product(name: "CustomDump", package: "swift-custom-dump")
            ]),
        .target(
            name: "TestFixtures",
            dependencies: ["Actomaton"] + (
                usesMainActorInTest ? [
                    .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras")
                ] : []
            ),
            path: "./Tests/TestFixtures"
        ),
        .testTarget(
            name: "ActomatonCoreTests",
            dependencies: ["ActomatonCore"]
        ),
        .testTarget(
            name: "ActomatonTests",
            dependencies: ["Actomaton", "TestFixtures"]
        ),
        .testTarget(
            name: "ActomatonUITests",
            dependencies: ["ActomatonUI", "TestFixtures"]
        ),
        .testTarget(
            name: "ReadMeTests",
            dependencies: ["Actomaton", "ActomatonDebugging"]
        )
    ],
    swiftLanguageModes: [.v6]
)

//for target in package.targets {
//    if target.swiftSettings == nil {
//        target.swiftSettings = []
//    }
//
//    // Simulates Linux build settings from macOS Xcode build.
//    target.swiftSettings?.append(.define("DISABLE_COMBINE"))
//
//    target.swiftSettings?.append(.enableUpcomingFeature("ExistentialAny"))
//}
