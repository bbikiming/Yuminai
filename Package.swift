// swift-tools-version: 6.1
// Yuminai SPM workspace.
//
// MVP-0에서는 SPM executable로 SwiftUI App을 빌드/실행한다 (`swift run YuminaiApp`).
// 정식 .app 번들/Xcode 프로젝트는 후속 — App/README.md 가이드 참조.
//
// **ADR-148** — swift-tools-version 6.2 → 6.1 다운그레이드 (CI 호환성).
// 실제 사용 기능 (StrictConcurrency, ExistentialAny upcoming features)은 모두 6.1+ 지원.
// macos-latest runner의 Xcode 16+ 시스템 toolchain (Swift 6.1)에서 빌드 가능.

import PackageDescription

let strict: [SwiftSetting] = [
    .enableUpcomingFeature("StrictConcurrency"),
    .enableUpcomingFeature("ExistentialAny")
]

let package = Package(
    name: "Yuminai",
    platforms: [
        // ADR-148 — .v26 (Swift 6.2 전용) → .v14 다운그레이드
        // Info.plist LSMinimumSystemVersion=14.0과 일치 + macos-latest CI runner 호환.
        // 사용자 시스템 macOS 26에서도 backward compat — macOS 14+ 모두 지원.
        .macOS(.v14)
    ],
    products: [
        .library(name: "YuminaiCore", targets: ["YuminaiCore"]),
        .library(name: "YuminaiClaudeAdapter", targets: ["YuminaiClaudeAdapter"]),
        .library(name: "YuminaiPersistence", targets: ["YuminaiPersistence"]),
        .library(name: "YuminaiUI", targets: ["YuminaiUI"]),
        .library(name: "YuminaiHarness", targets: ["YuminaiHarness"]),
        .library(name: "YuminaiTelegram", targets: ["YuminaiTelegram"]),
        .library(name: "YuminaiObsidian", targets: ["YuminaiObsidian"]),
        .executable(name: "YuminaiApp", targets: ["YuminaiApp"])
    ],
    dependencies: [
        // Notion급 마크다운 렌더링 — Apple swift-markdown 기반, MIT
        // ADR-021: 외부 의존성 정책 변경 — wrapping으로 lock-in 완화
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.0"),

        // SwiftTerm — Miguel de Icaza의 native Swift terminal emulator
        // ADR-027: v0.4 phase A의 embedded terminal pane, MIT
        // wrapping으로 lock-in 완화 — TerminalPane이 SwiftTerm을 직접 노출하지 않음
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.2.0"),

        // Highlightr — Highlight.js (100+ 언어) Swift wrap, NSAttributedString 반환, MIT
        // ADR-038 E1: viewer syntax highlight (editor는 raw TextEditor 유지)
        // wrapping으로 lock-in 완화 — CodeViewer가 Highlightr 직접 노출 X
        .package(url: "https://github.com/raspu/Highlightr", from: "2.1.0")
    ],
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
            dependencies: [
                "YuminaiCore",
                // ADR-148 — YuminaiUI/InspectorPanel.swift, MarkdownViewer.swift 등이
                // import YuminaiObsidian 사용. 로컬은 cache로 우회됐지만 CI fresh 빌드 실패.
                "YuminaiObsidian",
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "Highlightr", package: "Highlightr")
            ],
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
        .target(
            name: "YuminaiObsidian",
            dependencies: ["YuminaiCore"],
            path: "Sources/YuminaiObsidian",
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
                "YuminaiTelegram",
                "YuminaiObsidian"
            ],
            path: "Sources/YuminaiApp",
            swiftSettings: strict
        ),
        .testTarget(name: "YuminaiCoreTests", dependencies: ["YuminaiCore"], path: "Tests/YuminaiCoreTests"),
        .testTarget(name: "YuminaiClaudeAdapterTests", dependencies: ["YuminaiClaudeAdapter"], path: "Tests/YuminaiClaudeAdapterTests"),
        .testTarget(name: "YuminaiPersistenceTests", dependencies: ["YuminaiPersistence"], path: "Tests/YuminaiPersistenceTests"),
        .testTarget(name: "YuminaiUITests", dependencies: ["YuminaiUI"], path: "Tests/YuminaiUITests"),
        .testTarget(name: "YuminaiHarnessTests", dependencies: ["YuminaiHarness"], path: "Tests/YuminaiHarnessTests"),
        .testTarget(name: "YuminaiTelegramTests", dependencies: ["YuminaiTelegram"], path: "Tests/YuminaiTelegramTests"),
        .testTarget(name: "YuminaiObsidianTests", dependencies: ["YuminaiObsidian"], path: "Tests/YuminaiObsidianTests")
    ]
)
