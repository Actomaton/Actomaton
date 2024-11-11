// swift-tools-version:6.0

import Foundation
import PackageDescription

// `$ TEST_MAIN_ACTOR=1 swift test`
let usesMainActorInTest = ProcessInfo.processInfo.environment["TEST_MAIN_ACTOR"] == "1"

let package = Package(
    name: "Actomaton",
    platforms: [.macOS(.v10_15), .iOS(.v13), .watchOS(.v6), .tvOS(.v13)],
    products: [
        .library(
            name: "Actomaton",
            targets: ["Actomaton", "ActomatonDebugging"]),
        .library(
            name: "ActomatonUI",
            targets: ["ActomatonUI", "ActomatonDebugging"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-case-paths", from: "0.7.0"),
        .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.0.0")
    ] + (
        usesMainActorInTest ? [
            .package(url: "https://github.com/pointfreeco/swift-concurrency-extras", from: "1.1.0")
        ] : []
    ),
    targets: [
        .target(
            name: "Actomaton",
            dependencies: [.product(name: "CasePaths", package: "swift-case-paths")]
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
//}
