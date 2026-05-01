// swift-tools-version: 6.2
// Yuminai SPM workspace — 라이브러리 모듈만 정의.
// macOS App 타깃은 Xcode 프로젝트에서 별도로 만들고 이 Package를 Local Package로 추가한다.

import PackageDescription

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
        .library(name: "YuminaiHarness", targets: ["YuminaiHarness"])
    ],
    dependencies: [
        // MVP 외부 의존성 없음. 후속 검토:
        // - .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.2.0")
        // - .package(url: "https://github.com/groue/GRDB.swift", from: "6.0.0") — SwiftData 한계 시
    ],
    targets: [
        .target(
            name: "YuminaiCore",
            path: "Sources/YuminaiCore",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .target(
            name: "YuminaiClaudeAdapter",
            dependencies: ["YuminaiCore"],
            path: "Sources/YuminaiClaudeAdapter",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .target(
            name: "YuminaiPersistence",
            dependencies: ["YuminaiCore"],
            path: "Sources/YuminaiPersistence",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .target(
            name: "YuminaiUI",
            dependencies: ["YuminaiCore"],
            path: "Sources/YuminaiUI",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .target(
            name: "YuminaiHarness",
            dependencies: ["YuminaiCore"],
            path: "Sources/YuminaiHarness",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .testTarget(
            name: "YuminaiCoreTests",
            dependencies: ["YuminaiCore"],
            path: "Tests/YuminaiCoreTests"
        ),
        .testTarget(
            name: "YuminaiClaudeAdapterTests",
            dependencies: ["YuminaiClaudeAdapter"],
            path: "Tests/YuminaiClaudeAdapterTests"
        ),
        .testTarget(
            name: "YuminaiPersistenceTests",
            dependencies: ["YuminaiPersistence"],
            path: "Tests/YuminaiPersistenceTests"
        ),
        .testTarget(
            name: "YuminaiUITests",
            dependencies: ["YuminaiUI"],
            path: "Tests/YuminaiUITests"
        ),
        .testTarget(
            name: "YuminaiHarnessTests",
            dependencies: ["YuminaiHarness"],
            path: "Tests/YuminaiHarnessTests"
        )
    ]
)
