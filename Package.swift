// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "Actomaton",
    platforms: [.macOS(.v11), .iOS(.v13), .watchOS(.v6), .tvOS(.v13)],
    products: [
        .library(
            name: "Actomaton",
            targets: ["Actomaton"]),
        .library(
            name: "ActomatonUI",
            targets: ["ActomatonUI"]),
        .library(
            name: "ActomatonStore",
            targets: ["ActomatonStore", "ActomatonDebugging"])
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-case-paths", from: "0.7.0"),
        .package(url: "https://github.com/OpenCombine/OpenCombine", from: "0.12.0"),
//        .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "0.3.0"),
        .package(url: "https://github.com/inamiy/swift-custom-dump", branch: "SwiftWasm-inamiy"),
    ],
    targets: [
        .target(
            name: "Actomaton",
            dependencies: [
                .product(name: "CasePaths", package: "swift-case-paths"),
                .product(name: "OpenCombineShim", package: "OpenCombine", condition: .when(platforms: [.wasi])),
            ],
            swiftSettings: [
                .unsafeFlags([
                    "-Xfrontend", "-warn-concurrency",
                    "-Xfrontend", "-enable-actor-data-race-checks",
                ])
            ]
        ),
        .target(
            name: "ActomatonStore",
            dependencies: [
                "Actomaton"
            ],
            swiftSettings: [
                .unsafeFlags([
                    "-Xfrontend", "-warn-concurrency",
                    "-Xfrontend", "-enable-actor-data-race-checks",
                ])
            ]
        ),
        .target(
            name: "ActomatonUI",
            dependencies: [
                "Actomaton", "ActomatonDebugging"
            ],
            swiftSettings: [
                .unsafeFlags([
                    "-Xfrontend", "-warn-concurrency",
                    "-Xfrontend", "-enable-actor-data-race-checks",
                ])
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
            path: "./Tests/TestFixtures",
            swiftSettings: [
                .unsafeFlags([
                    "-Xfrontend", "-warn-concurrency",
                    "-Xfrontend", "-enable-actor-data-race-checks",
                ])
            ]
        ),
        .testTarget(
            name: "ActomatonTests",
            dependencies: ["Actomaton", "TestFixtures"],
            swiftSettings: [
                .unsafeFlags([
                    "-Xfrontend", "-warn-concurrency",
                    "-Xfrontend", "-enable-actor-data-race-checks",
                ])
            ]
        ),
        .testTarget(
            name: "ActomatonStoreTests",
            dependencies: ["ActomatonStore", "TestFixtures"],
            swiftSettings: [
                .unsafeFlags([
                    "-Xfrontend", "-warn-concurrency",
                    "-Xfrontend", "-enable-actor-data-race-checks",
                ])
            ]
        ),
        .testTarget(
            name: "ActomatonUITests",
            dependencies: ["ActomatonUI", "TestFixtures"],
            swiftSettings: [
                .unsafeFlags([
                    "-Xfrontend", "-warn-concurrency",
                    "-Xfrontend", "-enable-actor-data-race-checks",
                ])
            ]
        ),
        .testTarget(
            name: "ReadMeTests",
            dependencies: ["ActomatonStore", "ActomatonDebugging"],
            swiftSettings: [
                .unsafeFlags([
                    "-Xfrontend", "-warn-concurrency",
                    "-Xfrontend", "-enable-actor-data-race-checks",
                ])
            ]
        )
    ]
)

// MARK: - Tokamak integration

import Foundation

// WARNING: Depending on Tokamak will cause Xcode build error
// (only `swift build --triple wasm32-unknown-wasi` will succeed with SwiftWasm Toolchain)
//
// Can't build in Xcode (Redefinition of module 'FFI' error) · Issue #514 · TokamakUI/Tokamak
// https://github.com/TokamakUI/Tokamak/issues/514

//if ProcessInfo.processInfo.environment["CARTON"] != nil {
    package.dependencies.append(
        .package(url: "https://github.com/TokamakUI/Tokamak", from: "0.10.0")
    )

    let index = package.targets.firstIndex(where: { $0.name == "ActomatonUI" })
    if let index = index {
        package.targets[index].dependencies.append(
            .product(
                name: "TokamakShim",
                package: "Tokamak",
                condition: .when(platforms: [.wasi])
            )
        )
    }
//}
