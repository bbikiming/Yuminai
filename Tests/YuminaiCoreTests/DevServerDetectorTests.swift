import Foundation
import Testing
@testable import YuminaiCore

@Suite("DevServerDetector — package.json suggestions")
struct DevServerDetectorPackageJSONTests {
    @Test("Next.js scripts.dev → port 3000")
    func nextJsDetected() {
        let pkg: [String: Any] = [
            "scripts": ["dev": "next dev"]
        ]
        let result = DevServerDetector.suggestionsFromPackageJSON(pkg)
        #expect(result.contains { $0.framework == "Next.js" && $0.port == 3000 })
    }

    @Test("Vite scripts.dev → port 5173")
    func viteDetected() {
        let pkg: [String: Any] = [
            "scripts": ["dev": "vite"]
        ]
        let result = DevServerDetector.suggestionsFromPackageJSON(pkg)
        #expect(result.contains { $0.framework == "Vite" && $0.port == 5173 })
    }

    @Test("Angular ng serve → port 4200")
    func angularDetected() {
        let pkg: [String: Any] = [
            "scripts": ["start": "ng serve --open"]
        ]
        let result = DevServerDetector.suggestionsFromPackageJSON(pkg)
        #expect(result.contains { $0.framework == "Angular" && $0.port == 4200 })
    }

    @Test("Storybook → port 6006")
    func storybookDetected() {
        let pkg: [String: Any] = [
            "scripts": ["storybook": "storybook dev -p 6006"]
        ]
        let result = DevServerDetector.suggestionsFromPackageJSON(pkg)
        #expect(result.contains { $0.framework == "Storybook" && $0.port == 6006 })
    }

    @Test("Astro dev → port 4321")
    func astroDetected() {
        let pkg: [String: Any] = [
            "scripts": ["dev": "astro dev"]
        ]
        let result = DevServerDetector.suggestionsFromPackageJSON(pkg)
        #expect(result.contains { $0.framework == "Astro" && $0.port == 4321 })
    }

    @Test("dependencies fallback (scripts에 없을 때)")
    func dependenciesFallback() {
        let pkg: [String: Any] = [
            "scripts": ["test": "jest"],  // dev script 없음
            "dependencies": ["next": "14.0.0"]
        ]
        let result = DevServerDetector.suggestionsFromPackageJSON(pkg)
        #expect(result.contains { $0.framework == "Next.js" })
    }

    @Test("Confidence — high (script 명시) vs medium (deps fallback)")
    func confidenceLevels() {
        let scriptPkg: [String: Any] = ["scripts": ["dev": "vite"]]
        let scriptResult = DevServerDetector.suggestionsFromPackageJSON(scriptPkg)
        #expect(scriptResult.first?.confidence == .high)

        let depsPkg: [String: Any] = [
            "scripts": ["test": "jest"],
            "devDependencies": ["vite": "5.0.0"]
        ]
        let depsResult = DevServerDetector.suggestionsFromPackageJSON(depsPkg)
        #expect(depsResult.first?.confidence == .medium)
    }

    @Test("빈 package.json은 빈 결과")
    func emptyPackageJSON() {
        let pkg: [String: Any] = [:]
        #expect(DevServerDetector.suggestionsFromPackageJSON(pkg).isEmpty)
    }
}

@Suite("DevServerDetector — config files")
struct DevServerDetectorConfigTests {
    @Test("vite.config.ts 존재 → Vite suggestion")
    func viteConfig() throws {
        let temp = try makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: temp) }
        try "// vite config".write(to: temp.appending(path: "vite.config.ts"), atomically: true, encoding: .utf8)

        let result = DevServerDetector.suggestionsFromConfigFiles(temp)
        #expect(result.contains { $0.framework == "Vite" })
    }

    @Test("config 파일 없으면 빈 결과")
    func noConfig() throws {
        let temp = try makeTempWorkspace()
        defer { try? FileManager.default.removeItem(at: temp) }
        let result = DevServerDetector.suggestionsFromConfigFiles(temp)
        #expect(result.isEmpty)
    }

    private func makeTempWorkspace() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "yuminai-devserver-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

@Suite("DevServerDetector — end-to-end")
struct DevServerDetectorE2ETests {
    @Test("실제 워크스페이스 path → 중복 제거된 결과")
    func endToEnd() throws {
        let temp = FileManager.default.temporaryDirectory
            .appending(path: "yuminai-detector-e2e-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        // package.json + vite.config.ts (둘 다 Vite → 중복)
        let pkgJSON = """
        {"scripts": {"dev": "vite"}, "devDependencies": {"vite": "5.0.0"}}
        """
        try pkgJSON.write(to: temp.appending(path: "package.json"), atomically: true, encoding: .utf8)
        try "config".write(to: temp.appending(path: "vite.config.ts"), atomically: true, encoding: .utf8)

        let detector = DevServerDetector(workspacePath: temp.path)
        let result = detector.detect()

        // port 5173가 1번만 (중복 제거)
        let viteCount = result.filter { $0.port == 5173 }.count
        #expect(viteCount == 1)
    }
}
