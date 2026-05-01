// swift-tools-version: 6.2
// Yuminai SPM workspace.
//
// MVP-0에서는 SPM executable로 SwiftUI App을 빌드/실행한다 (`swift run YuminaiApp`).
// 정식 .app 번들/Xcode 프로젝트는 후속 — App/README.md 가이드 참조.

import PackageDescription

let strict: [SwiftSetting] = [
    .enableUpcomingFeature("StrictConcurrency"),
    .enableUpcomingFeature("ExistentialAny")
]

let package = Package(
    name: "Yuminai",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "YuminaiCore", targets: ["YuminaiCore"]),
        .library(name: "YuminaiClaudeAdapter", targets: ["YuminaiClaudeAdapter"]),
        .library(name: "YuminaiPersistence", targets: ["YuminaiPersistence"]),
        .library(name: "YuminaiUI", targets: ["YuminaiUI"]),
        .library(name: "YuminaiHarness", targets: ["YuminaiHarness"]),
        .library(name: "YuminaiTelegram", targets: ["YuminaiTelegram"]),
        .executable(name: "YuminaiApp", targets: ["YuminaiApp"])
    ],
    dependencies: [],
    targets: [
        .target(name: "YuminaiCore", path: "Sources/YuminaiCore", swiftSettings: strict),
        .target(
            name: "YuminaiClaudeAdapter",
            dependencies: ["YuminaiCore"],
            path: "Sources/YuminaiClaudeAdapter",
            swiftSettings: strict
        ),
        .target(
            name: "YuminaiPersistence",
            dependencies: ["YuminaiCore"],
            path: "Sources/YuminaiPersistence",
            swiftSettings: strict
        ),
        .target(
            name: "YuminaiUI",
            dependencies: ["YuminaiCore"],
            path: "Sources/YuminaiUI",
            swiftSettings: strict
        ),
        .target(
            name: "YuminaiHarness",
            dependencies: ["YuminaiCore"],
            path: "Sources/YuminaiHarness",
            swiftSettings: strict
        ),
        .target(
            name: "YuminaiTelegram",
            dependencies: ["YuminaiCore"],
            path: "Sources/YuminaiTelegram",
            swiftSettings: strict
        ),
        .executableTarget(
            name: "YuminaiApp",
            dependencies: [
                "YuminaiCore",
                "YuminaiClaudeAdapter",
                "YuminaiPersistence",
                "YuminaiUI",
                "YuminaiHarness",
                "YuminaiTelegram"
            ],
            path: "Sources/YuminaiApp",
            swiftSettings: strict
        ),
        .testTarget(name: "YuminaiCoreTests", dependencies: ["YuminaiCore"], path: "Tests/YuminaiCoreTests"),
        .testTarget(name: "YuminaiClaudeAdapterTests", dependencies: ["YuminaiClaudeAdapter"], path: "Tests/YuminaiClaudeAdapterTests"),
        .testTarget(name: "YuminaiPersistenceTests", dependencies: ["YuminaiPersistence"], path: "Tests/YuminaiPersistenceTests"),
        .testTarget(name: "YuminaiUITests", dependencies: ["YuminaiUI"], path: "Tests/YuminaiUITests"),
        .testTarget(name: "YuminaiHarnessTests", dependencies: ["YuminaiHarness"], path: "Tests/YuminaiHarnessTests"),
        .testTarget(name: "YuminaiTelegramTests", dependencies: ["YuminaiTelegram"], path: "Tests/YuminaiTelegramTests")
    ]
)
