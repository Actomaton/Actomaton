// swift-tools-version:6.2

import Foundation
import PackageDescription

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
        .library(
            name: "ActomatonTesting",
            targets: ["ActomatonTesting"]
        ),
    ],
    dependencies: {
        var deps: [Package.Dependency] = [
            .package(url: "https://github.com/pointfreeco/swift-case-paths", from: "0.7.0"),
            .package(url: "https://github.com/pointfreeco/swift-clocks", from: "1.0.6"),
            .package(url: "https://github.com/pointfreeco/swift-concurrency-extras", from: "1.1.0"),
            .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.0.0"),
        ]
        if ProcessInfo.processInfo.environment["DOCC"] != nil {
            deps.append(.package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.6"))
        }
        if ProcessInfo.processInfo.environment["SWIFTFORMAT"] != nil {
            deps.append(.package(url: "https://github.com/nicklockwood/SwiftFormat", from: "0.55.3"))
        }
        return deps
    }(),
    targets: [
        .target(
            name: "ActomatonCore",
            dependencies: []
        ),
        .target(
            name: "ActomatonEffect",
            dependencies: [
                "ActomatonCore",
                .product(name: "Clocks", package: "swift-clocks"),
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
            name: "ActomatonTesting",
            dependencies: [
                "ActomatonCore",
                "ActomatonEffect",
                .product(name: "CustomDump", package: "swift-custom-dump"),
            ]
        ),
        .target(
            name: "TestFixtures",
            dependencies: [
                "Actomaton",
                .product(name: "Clocks", package: "swift-clocks"),
                .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras")
            ],
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
            name: "ActomatonTestingTests",
            dependencies: ["ActomatonTesting", "TestFixtures"]
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
