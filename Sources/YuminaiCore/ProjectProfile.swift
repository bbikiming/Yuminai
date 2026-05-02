import Foundation

/// 워크스페이스 프로젝트 프로필 (ADR-048).
///
/// **목적**: 새 워크스페이스/워크트리 시작 시 platform/언어/백엔드 등 메타정보를 수집해
/// Harness가 적절한 모델 routing + system context를 구성할 수 있게 함.
///
/// **수집 시점**:
/// - 워크스페이스 생성 sheet에서 사용자 선택 (큰 분류만)
/// - 디스크 자동 감지 (package.json, Package.swift 등) — 기본값 채움
///
/// **활용**:
/// - HandoffPromptBuilder가 system context에 포함 ("이 프로젝트는 Next.js + TypeScript + PostgreSQL")
/// - ModelCapabilityMatrix가 platform/언어 별 모델 가중치 보정 (예: SwiftUI → Claude 강화)
public struct ProjectProfile: Sendable, Codable, Hashable {
    public var platform: ProjectPlatform
    public var primaryLanguage: ProjectLanguage
    public var secondaryLanguages: [ProjectLanguage]
    public var hasBackend: Bool
    public var backendLanguage: ProjectLanguage?
    public var frameworks: [String]
    public var testFramework: String?
    /// 사용자 자유 입력 — 프로젝트 특이사항 (system context에 그대로 포함).
    public var notes: String

    public init(
        platform: ProjectPlatform = .unknown,
        primaryLanguage: ProjectLanguage = .unknown,
        secondaryLanguages: [ProjectLanguage] = [],
        hasBackend: Bool = false,
        backendLanguage: ProjectLanguage? = nil,
        frameworks: [String] = [],
        testFramework: String? = nil,
        notes: String = ""
    ) {
        self.platform = platform
        self.primaryLanguage = primaryLanguage
        self.secondaryLanguages = secondaryLanguages
        self.hasBackend = hasBackend
        self.backendLanguage = backendLanguage
        self.frameworks = frameworks
        self.testFramework = testFramework
        self.notes = notes
    }

    public static let empty = ProjectProfile()

    /// HandoffPromptBuilder + ModelCapabilityMatrix용 system context 한 줄.
    /// 예: "Next.js + TypeScript 웹 / PostgreSQL 백엔드 / Jest 테스트"
    public func systemContextSummary() -> String {
        var parts: [String] = []
        // Platform + primary language
        if platform != .unknown {
            parts.append("\(platform.displayName)")
        }
        if primaryLanguage != .unknown {
            parts.append(primaryLanguage.displayName)
        }
        // Frameworks
        if !frameworks.isEmpty {
            parts.append(frameworks.joined(separator: " + "))
        }
        // Backend
        if hasBackend, let backend = backendLanguage, backend != .unknown {
            parts.append("\(backend.displayName) 백엔드")
        } else if hasBackend {
            parts.append("백엔드 포함")
        }
        // Test
        if let test = testFramework, !test.isEmpty {
            parts.append("\(test) 테스트")
        }
        // Notes
        if !notes.isEmpty {
            parts.append("note: \(notes)")
        }
        return parts.isEmpty ? "(프로필 미설정)" : parts.joined(separator: " / ")
    }
}

/// 프로젝트 platform 대분류.
public enum ProjectPlatform: String, Sendable, Codable, Hashable, CaseIterable {
    case web
    case iosApp = "ios"
    case androidApp = "android"
    case macosApp = "macos"
    case desktopCrossPlatform = "desktop"
    case cli
    case library
    case backend         // 백엔드 단독 (API server)
    case mobile          // React Native / Flutter cross-platform
    case dataScience
    case unknown

    public var displayName: String {
        switch self {
        case .web: return "웹"
        case .iosApp: return "iOS 앱"
        case .androidApp: return "Android 앱"
        case .macosApp: return "macOS 앱"
        case .desktopCrossPlatform: return "데스크탑 (cross-platform)"
        case .cli: return "CLI"
        case .library: return "라이브러리"
        case .backend: return "백엔드 서버"
        case .mobile: return "모바일 (cross-platform)"
        case .dataScience: return "데이터 사이언스"
        case .unknown: return "미정"
        }
    }
}

/// 프로젝트 언어 (대분류).
public enum ProjectLanguage: String, Sendable, Codable, Hashable, CaseIterable {
    case typescript
    case javascript
    case swift
    case kotlin
    case java
    case python
    case go
    case rust
    case cpp
    case csharp
    case ruby
    case php
    case dart
    case elixir
    case clojure
    case haskell
    case other
    case unknown

    public var displayName: String {
        switch self {
        case .typescript: return "TypeScript"
        case .javascript: return "JavaScript"
        case .swift: return "Swift"
        case .kotlin: return "Kotlin"
        case .java: return "Java"
        case .python: return "Python"
        case .go: return "Go"
        case .rust: return "Rust"
        case .cpp: return "C++"
        case .csharp: return "C#"
        case .ruby: return "Ruby"
        case .php: return "PHP"
        case .dart: return "Dart"
        case .elixir: return "Elixir"
        case .clojure: return "Clojure"
        case .haskell: return "Haskell"
        case .other: return "기타"
        case .unknown: return "미정"
        }
    }
}

// MARK: - ProjectProfileDetector

/// 디스크에서 프로젝트 시그너처 파일 감지 → 기본 ProjectProfile 추정.
public enum ProjectProfileDetector {
    /// 워크스페이스 디렉토리에서 감지 가능한 marker 파일 검사 후 ProjectProfile 반환.
    /// caller가 사용자 confirm 후 저장 (자동 적용 X — UI sheet에서 미리채움 용도).
    public static func detect(at directoryPath: String) -> ProjectProfile {
        let fm = FileManager.default
        let dir = URL(fileURLWithPath: directoryPath)
        var profile = ProjectProfile()

        func exists(_ name: String) -> Bool {
            fm.fileExists(atPath: dir.appending(path: name).path)
        }

        func contents(_ name: String) -> String? {
            try? String(contentsOf: dir.appending(path: name), encoding: .utf8)
        }

        // 1. Package.swift → Swift
        if exists("Package.swift") {
            profile.primaryLanguage = .swift
            profile.platform = .library  // default — overridden below
            profile.testFramework = "Swift Testing / XCTest"
            // SwiftUI / iOS hint
            if let pkg = contents("Package.swift") {
                if pkg.contains(".iOS(") || pkg.contains("UIKit") {
                    profile.platform = .iosApp
                }
                if pkg.contains(".macOS(") || pkg.contains("AppKit") {
                    profile.platform = .macosApp
                }
            }
            return profile
        }

        // 2. *.xcodeproj → iOS/macOS
        if let entries = try? fm.contentsOfDirectory(atPath: directoryPath),
           entries.contains(where: { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }) {
            profile.primaryLanguage = .swift
            profile.platform = .iosApp  // default
            profile.testFramework = "XCTest"
            return profile
        }

        // 3. package.json → JS/TS
        if exists("package.json"), let pkg = contents("package.json") {
            profile.primaryLanguage = pkg.contains("\"typescript\"") || exists("tsconfig.json") ? .typescript : .javascript
            profile.platform = .web  // default
            // Framework detection
            var fwks: [String] = []
            if pkg.contains("\"next\"") { fwks.append("Next.js") }
            if pkg.contains("\"react\"") && !pkg.contains("\"next\"") { fwks.append("React") }
            if pkg.contains("\"vue\"") { fwks.append("Vue") }
            if pkg.contains("\"svelte\"") { fwks.append("Svelte") }
            if pkg.contains("\"angular\"") { fwks.append("Angular") }
            if pkg.contains("\"react-native\"") {
                fwks.append("React Native")
                profile.platform = .mobile
            }
            if pkg.contains("\"expo\"") {
                fwks.append("Expo")
                profile.platform = .mobile
            }
            if pkg.contains("\"electron\"") {
                fwks.append("Electron")
                profile.platform = .desktopCrossPlatform
            }
            if pkg.contains("\"express\"") || pkg.contains("\"fastify\"") || pkg.contains("\"nestjs\"") {
                profile.hasBackend = true
                profile.backendLanguage = profile.primaryLanguage
            }
            if pkg.contains("\"jest\"") { profile.testFramework = "Jest" }
            else if pkg.contains("\"vitest\"") { profile.testFramework = "Vitest" }
            profile.frameworks = fwks
            return profile
        }

        // 4. Cargo.toml → Rust
        if exists("Cargo.toml") {
            profile.primaryLanguage = .rust
            profile.platform = .cli  // default
            profile.testFramework = "cargo test"
            if let cargo = contents("Cargo.toml") {
                if cargo.contains("[lib]") { profile.platform = .library }
                if cargo.contains("axum") || cargo.contains("actix-web") || cargo.contains("rocket") {
                    profile.hasBackend = true
                    profile.backendLanguage = .rust
                    profile.platform = .backend
                }
            }
            return profile
        }

        // 5. go.mod → Go
        if exists("go.mod") {
            profile.primaryLanguage = .go
            profile.platform = .cli
            profile.testFramework = "go test"
            return profile
        }

        // 6. pyproject.toml / requirements.txt → Python
        if exists("pyproject.toml") || exists("requirements.txt") || exists("Pipfile") {
            profile.primaryLanguage = .python
            profile.platform = .cli
            profile.testFramework = "pytest"
            if let req = contents("requirements.txt") {
                if req.contains("django") {
                    profile.frameworks.append("Django")
                    profile.hasBackend = true
                    profile.backendLanguage = .python
                }
                if req.contains("fastapi") || req.contains("flask") {
                    profile.frameworks.append(req.contains("fastapi") ? "FastAPI" : "Flask")
                    profile.hasBackend = true
                    profile.backendLanguage = .python
                    profile.platform = .backend
                }
                if req.contains("pandas") || req.contains("numpy") {
                    profile.platform = .dataScience
                }
            }
            return profile
        }

        // 7. build.gradle / build.gradle.kts → Kotlin/Java
        if exists("build.gradle") || exists("build.gradle.kts") || exists("settings.gradle") || exists("settings.gradle.kts") {
            let isKotlin = exists("build.gradle.kts") || exists("settings.gradle.kts")
            profile.primaryLanguage = isKotlin ? .kotlin : .java
            profile.platform = .androidApp  // default if Android Manifest present
            if !exists("AndroidManifest.xml") &&
               !(try? fm.contentsOfDirectory(atPath: directoryPath))!.contains(where: { $0 == "app" }) {
                profile.platform = .backend  // Spring Boot 추정
                if let buildFile = contents("build.gradle.kts") ?? contents("build.gradle"),
                   buildFile.contains("spring-boot") {
                    profile.frameworks.append("Spring Boot")
                    profile.hasBackend = true
                    profile.backendLanguage = profile.primaryLanguage
                }
            }
            return profile
        }

        // 8. pubspec.yaml → Dart/Flutter
        if exists("pubspec.yaml") {
            profile.primaryLanguage = .dart
            profile.platform = .mobile
            profile.frameworks = ["Flutter"]
            profile.testFramework = "flutter test"
            return profile
        }

        // 9. Gemfile → Ruby
        if exists("Gemfile") {
            profile.primaryLanguage = .ruby
            profile.platform = .web
            if let gemfile = contents("Gemfile"), gemfile.contains("rails") {
                profile.frameworks = ["Rails"]
                profile.hasBackend = true
                profile.backendLanguage = .ruby
            }
            return profile
        }

        // 10. composer.json → PHP
        if exists("composer.json") {
            profile.primaryLanguage = .php
            profile.platform = .web
            if let json = contents("composer.json"), json.contains("laravel") {
                profile.frameworks = ["Laravel"]
                profile.hasBackend = true
                profile.backendLanguage = .php
            }
            return profile
        }

        // No marker — return empty profile (사용자 manual 입력)
        return profile
    }
}
