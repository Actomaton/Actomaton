// swift-tools-version:5.9

import PackageDescription

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
        .library(
            name: "ActomatonStore",
            targets: ["ActomatonStore", "ActomatonDebugging"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-case-paths", from: "0.7.0"),
        .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "0.3.0")
    ],
    targets: [
        .target(
            name: "Actomaton",
            dependencies: [.product(name: "CasePaths", package: "swift-case-paths")]
        ),
        .target(
            name: "ActomatonStore",
            dependencies: [
                "Actomaton"
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
            dependencies: ["Actomaton"],
            path: "./Tests/TestFixtures"
        ),
        .testTarget(
            name: "ActomatonTests",
            dependencies: ["Actomaton", "TestFixtures"]
        ),
        .testTarget(
            name: "ActomatonStoreTests",
            dependencies: ["ActomatonStore", "TestFixtures"]
        ),
        .testTarget(
            name: "ActomatonUITests",
            dependencies: ["ActomatonUI", "TestFixtures"]
        ),
        .testTarget(
            name: "ReadMeTests",
            dependencies: ["ActomatonStore", "ActomatonDebugging"]
        )
    ]
)

// Comment-Out: Enable this `unsafeFlags` in local development.
//
//for target in package.targets where target.type != .system {
//    target.swiftSettings = target.swiftSettings ?? []
//    target.swiftSettings?.append(
//        .unsafeFlags([
//            "-Xfrontend", "-strict-concurrency=complete",
//        ])
//    )
//}
