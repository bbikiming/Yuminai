import Foundation
import Testing
@testable import YuminaiCore

@Suite("ProjectProfile — model + summary (ADR-048)")
struct ProjectProfileTests {
    @Test("empty profile은 platform/language unknown")
    func emptyProfile() {
        let p = ProjectProfile.empty
        #expect(p.platform == .unknown)
        #expect(p.primaryLanguage == .unknown)
        #expect(p.hasBackend == false)
        #expect(p.frameworks.isEmpty)
    }

    @Test("systemContextSummary는 미설정 시 placeholder")
    func emptySummary() {
        #expect(ProjectProfile.empty.systemContextSummary() == "(프로필 미설정)")
    }

    @Test("systemContextSummary 일반 케이스 (web + TypeScript + Next.js + PostgreSQL)")
    func fullSummary() {
        let p = ProjectProfile(
            platform: .web,
            primaryLanguage: .typescript,
            hasBackend: true,
            backendLanguage: .typescript,
            frameworks: ["Next.js", "Tailwind"],
            testFramework: "Jest",
            notes: "ADR 우선"
        )
        let summary = p.systemContextSummary()
        #expect(summary.contains("웹"))
        #expect(summary.contains("TypeScript"))
        #expect(summary.contains("Next.js + Tailwind"))
        #expect(summary.contains("백엔드"))
        #expect(summary.contains("Jest"))
        #expect(summary.contains("ADR 우선"))
    }

    @Test("Codable round-trip 보존")
    func codableRoundTrip() throws {
        let p = ProjectProfile(
            platform: .iosApp,
            primaryLanguage: .swift,
            hasBackend: false,
            frameworks: ["SwiftUI", "Combine"],
            testFramework: "XCTest"
        )
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(ProjectProfile.self, from: data)
        #expect(decoded == p)
    }
}

@Suite("ProjectProfileDetector — 디스크 자동 감지 (ADR-048)")
struct ProjectProfileDetectorTests {
    private static func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "yuminai-profile-detect-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Package.swift만 있으면 Swift library")
    func detectSwiftPackage() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "// swift-tools-version:5.9\nimport PackageDescription".write(
            to: dir.appending(path: "Package.swift"),
            atomically: true, encoding: .utf8
        )
        let p = ProjectProfileDetector.detect(at: dir.path)
        #expect(p.primaryLanguage == .swift)
        #expect(p.platform == .library)
    }

    @Test("Package.swift + iOS 의존성 → iOS app")
    func detectSwiftPackageIOS() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try """
        // swift-tools-version:5.9
        import PackageDescription
        let package = Package(
            name: "MyApp",
            platforms: [.iOS(.v17)],
            ...
        )
        """.write(to: dir.appending(path: "Package.swift"), atomically: true, encoding: .utf8)
        let p = ProjectProfileDetector.detect(at: dir.path)
        #expect(p.platform == .iosApp)
    }

    @Test("package.json + typescript + next → Next.js TS web")
    func detectNextJsTypeScript() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try """
        {
          "dependencies": {
            "next": "14",
            "react": "18",
            "typescript": "5"
          }
        }
        """.write(to: dir.appending(path: "package.json"), atomically: true, encoding: .utf8)
        let p = ProjectProfileDetector.detect(at: dir.path)
        #expect(p.primaryLanguage == .typescript)
        #expect(p.platform == .web)
        #expect(p.frameworks.contains("Next.js"))
    }

    @Test("package.json + react-native → mobile (Expo)")
    func detectReactNative() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try """
        {
          "dependencies": {
            "react-native": "0.74",
            "expo": "51",
            "typescript": "5"
          }
        }
        """.write(to: dir.appending(path: "package.json"), atomically: true, encoding: .utf8)
        let p = ProjectProfileDetector.detect(at: dir.path)
        #expect(p.platform == .mobile)
        #expect(p.frameworks.contains("React Native"))
        #expect(p.frameworks.contains("Expo"))
    }

    @Test("package.json + express → 백엔드 검출")
    func detectExpressBackend() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try """
        {"dependencies":{"express":"4","typescript":"5"}}
        """.write(to: dir.appending(path: "package.json"), atomically: true, encoding: .utf8)
        let p = ProjectProfileDetector.detect(at: dir.path)
        #expect(p.hasBackend)
        #expect(p.backendLanguage == .typescript)
    }

    @Test("Cargo.toml → Rust CLI")
    func detectRust() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "[package]\nname = \"x\"".write(
            to: dir.appending(path: "Cargo.toml"),
            atomically: true, encoding: .utf8
        )
        let p = ProjectProfileDetector.detect(at: dir.path)
        #expect(p.primaryLanguage == .rust)
        #expect(p.platform == .cli)
    }

    @Test("pyproject.toml → Python")
    func detectPython() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "[project]\nname = \"x\"".write(
            to: dir.appending(path: "pyproject.toml"),
            atomically: true, encoding: .utf8
        )
        let p = ProjectProfileDetector.detect(at: dir.path)
        #expect(p.primaryLanguage == .python)
    }

    @Test("requirements.txt + django → Django backend")
    func detectDjango() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "django==4.2\nrequests".write(
            to: dir.appending(path: "requirements.txt"),
            atomically: true, encoding: .utf8
        )
        let p = ProjectProfileDetector.detect(at: dir.path)
        #expect(p.primaryLanguage == .python)
        #expect(p.frameworks.contains("Django"))
        #expect(p.hasBackend)
    }

    @Test("pubspec.yaml → Flutter mobile")
    func detectFlutter() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "name: my_app\ndependencies:\n  flutter:\n    sdk: flutter".write(
            to: dir.appending(path: "pubspec.yaml"),
            atomically: true, encoding: .utf8
        )
        let p = ProjectProfileDetector.detect(at: dir.path)
        #expect(p.primaryLanguage == .dart)
        #expect(p.platform == .mobile)
        #expect(p.frameworks.contains("Flutter"))
    }

    @Test("아무 marker 없으면 empty profile")
    func detectEmpty() throws {
        let dir = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "hello".write(to: dir.appending(path: "README.md"), atomically: true, encoding: .utf8)
        let p = ProjectProfileDetector.detect(at: dir.path)
        #expect(p.platform == .unknown)
        #expect(p.primaryLanguage == .unknown)
    }
}
