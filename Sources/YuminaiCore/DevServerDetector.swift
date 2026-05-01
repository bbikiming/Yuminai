import Foundation

/// 워크스페이스 dev server URL 자동 감지 (ADR-035 B1, PreviewPane).
///
/// **방법**:
/// 1. `package.json` "scripts.dev"/"scripts.start" 분석 → 알려진 framework default port
/// 2. config 파일 (vite.config / next.config / nuxt.config) 추정
/// 3. 사용자에게 추천 (확정은 Preview에서 직접 입력)
///
/// 단순화 — 실제 ping은 안 함 (사용자가 직접 시작했는지 확신 X). UX는 "추천만".
public struct DevServerDetector: Sendable {
    public let workspacePath: String

    public init(workspacePath: String) {
        self.workspacePath = workspacePath
    }

    public func detect() -> [Suggestion] {
        var results: [Suggestion] = []
        let workspaceURL = URL(fileURLWithPath: workspacePath)

        // 1) package.json 분석
        if let pkg = readPackageJSON(workspaceURL) {
            results.append(contentsOf: Self.suggestionsFromPackageJSON(pkg))
        }
        // 2) config 파일 추정
        results.append(contentsOf: Self.suggestionsFromConfigFiles(workspaceURL))

        // 중복 제거 (port 기준)
        var seen = Set<Int>()
        return results.filter { seen.insert($0.port).inserted }
    }

    public struct Suggestion: Sendable, Equatable, Identifiable {
        public let id: String
        public let framework: String
        public let port: Int
        public let url: String
        public let confidence: Confidence

        public enum Confidence: Sendable, Equatable {
            case high       // package.json에 명시
            case medium     // config 파일 발견
            case low        // 일반적 default

            public var label: String {
                switch self {
                case .high: return "확실"
                case .medium: return "추정"
                case .low: return "일반"
                }
            }
        }

        public init(framework: String, port: Int, confidence: Confidence) {
            self.id = "\(framework):\(port)"
            self.framework = framework
            self.port = port
            self.url = "http://localhost:\(port)"
            self.confidence = confidence
        }
    }

    // MARK: - Internal

    private func readPackageJSON(_ workspace: URL) -> [String: Any]? {
        let path = workspace.appending(path: "package.json")
        guard let data = try? Data(contentsOf: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json
    }

    static func suggestionsFromPackageJSON(_ pkg: [String: Any]) -> [Suggestion] {
        var suggestions: [Suggestion] = []
        let scripts = pkg["scripts"] as? [String: Any] ?? [:]
        let allScripts = scripts.values.compactMap { $0 as? String }.joined(separator: " ").lowercased()

        // scripts에서 framework 추정
        if allScripts.contains("next ") || allScripts.contains("next dev") {
            suggestions.append(.init(framework: "Next.js", port: 3000, confidence: .high))
        }
        if allScripts.contains("vite") {
            suggestions.append(.init(framework: "Vite", port: 5173, confidence: .high))
        }
        if allScripts.contains("nuxt") {
            suggestions.append(.init(framework: "Nuxt", port: 3000, confidence: .high))
        }
        if allScripts.contains("react-scripts start") {
            suggestions.append(.init(framework: "Create React App", port: 3000, confidence: .high))
        }
        if allScripts.contains("ng serve") {
            suggestions.append(.init(framework: "Angular", port: 4200, confidence: .high))
        }
        if allScripts.contains("svelte-kit") || allScripts.contains("vite") && (allScripts.contains("svelte")) {
            suggestions.append(.init(framework: "SvelteKit", port: 5173, confidence: .high))
        }
        if allScripts.contains("astro dev") {
            suggestions.append(.init(framework: "Astro", port: 4321, confidence: .high))
        }
        if allScripts.contains("remix ") {
            suggestions.append(.init(framework: "Remix", port: 3000, confidence: .high))
        }
        if allScripts.contains("storybook") {
            suggestions.append(.init(framework: "Storybook", port: 6006, confidence: .high))
        }
        if allScripts.contains("docusaurus start") {
            suggestions.append(.init(framework: "Docusaurus", port: 3000, confidence: .high))
        }

        // dependencies로 fallback (scripts 못 읽으면)
        if suggestions.isEmpty {
            let deps = (pkg["dependencies"] as? [String: Any] ?? [:])
            let devDeps = (pkg["devDependencies"] as? [String: Any] ?? [:])
            let allDeps = Array(deps.keys) + Array(devDeps.keys)
            if allDeps.contains("next") {
                suggestions.append(.init(framework: "Next.js", port: 3000, confidence: .medium))
            } else if allDeps.contains("vite") {
                suggestions.append(.init(framework: "Vite", port: 5173, confidence: .medium))
            } else if allDeps.contains("@angular/core") {
                suggestions.append(.init(framework: "Angular", port: 4200, confidence: .medium))
            }
        }

        return suggestions
    }

    static func suggestionsFromConfigFiles(_ workspace: URL) -> [Suggestion] {
        let fm = FileManager.default
        var suggestions: [Suggestion] = []

        // 알려진 config 파일 → framework
        let knownConfigs: [(String, String, Int)] = [
            ("vite.config.ts", "Vite", 5173),
            ("vite.config.js", "Vite", 5173),
            ("next.config.js", "Next.js", 3000),
            ("next.config.ts", "Next.js", 3000),
            ("next.config.mjs", "Next.js", 3000),
            ("nuxt.config.ts", "Nuxt", 3000),
            ("svelte.config.js", "SvelteKit", 5173),
            ("astro.config.mjs", "Astro", 4321),
            ("angular.json", "Angular", 4200)
        ]

        for (filename, framework, port) in knownConfigs {
            let path = workspace.appending(path: filename).path
            if fm.fileExists(atPath: path) {
                suggestions.append(.init(framework: framework, port: port, confidence: .medium))
            }
        }

        return suggestions
    }
}
