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

    public struct Suggestion: Sendable, Equatable, Identifiable, Hashable {
        public let id: String
        public let framework: String
        public let port: Int
        public let url: String
        public let confidence: Confidence
        /// live ping 결과 — nil = 미확인, true = 응답 OK, false = 응답 X (ADR-036 C1)
        public var isAlive: Bool?

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

        public init(framework: String, port: Int, confidence: Confidence, isAlive: Bool? = nil) {
            self.id = "\(framework):\(port)"
            self.framework = framework
            self.port = port
            self.url = "http://localhost:\(port)"
            self.confidence = confidence
            self.isAlive = isAlive
        }
    }

    /// suggestions 각각에 ping 결과 채우기 (ADR-036 C1).
    /// HEAD request, 짧은 timeout (300ms), 실패해도 silent (isAlive = false).
    public static func pingAll(_ suggestions: [Suggestion]) async -> [Suggestion] {
        await withTaskGroup(of: (Suggestion, Bool?).self, returning: [Suggestion].self) { group in
            for sug in suggestions {
                group.addTask {
                    let alive = await ping(url: sug.url)
                    return (sug, alive)
                }
            }
            var result: [Suggestion] = []
            for await (sug, alive) in group {
                var updated = sug
                updated.isAlive = alive
                result.append(updated)
            }
            // confidence 순서 유지를 위해 원본 순서로 재정렬
            return suggestions.compactMap { original in
                result.first { $0.id == original.id }
            }
        }
    }

    private static func ping(url: String) async -> Bool {
        guard let url = URL(string: url) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 0.3
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            // 2xx/3xx/4xx 모두 살아있는 것으로 간주 (5xx만 실패)
            if let http = response as? HTTPURLResponse {
                return http.statusCode < 500
            }
            return true
        } catch {
            return false
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
