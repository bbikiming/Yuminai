import Foundation

/// File-name fuzzy filter — Cmd+P style (ADR-038 E3).
///
/// **점수 체계**:
/// - prefix match (이름이 query로 시작): 100점
/// - name contains: 50점
/// - path contains: 20점 (이름엔 없지만 경로에 있는 경우 — 예: "src/auth.ts" + query "auth")
/// - 짧은 이름 가산점: max(0, 50 - name.count) — 정확한 매칭 우선
///
/// 빈 query → 전체 (score 0, path 알파벳 정렬)
public enum FuzzyFileFilter {
    public struct Match: Equatable, Hashable, Sendable {
        public let path: String
        public let name: String
        public let score: Int

        public init(path: String, name: String, score: Int) {
            self.path = path
            self.name = name
            self.score = score
        }
    }

    public struct Candidate: Equatable, Hashable, Sendable {
        public let path: String
        public let name: String

        public init(path: String, name: String) {
            self.path = path
            self.name = name
        }
    }

    /// Tree (FileNode)에서 binary가 아닌 파일들만 추출 (folder는 제외).
    public static func flatten(_ tree: [FileNode]) -> [Candidate] {
        var result: [Candidate] = []
        func walk(_ nodes: [FileNode]) {
            for node in nodes {
                switch node {
                case .file(let name, let path, _, _, let isBinary):
                    if !isBinary {
                        result.append(Candidate(path: path, name: name))
                    }
                case .folder(_, _, let children):
                    walk(children)
                }
            }
        }
        walk(tree)
        return result
    }

    /// Fuzzy 점수 계산 + 정렬된 Match 리스트 반환.
    public static func filter(query: String, candidates: [Candidate]) -> [Match] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            return candidates
                .map { Match(path: $0.path, name: $0.name, score: 0) }
                .sorted { $0.path < $1.path }
        }
        var results: [Match] = []
        for candidate in candidates {
            let nameLower = candidate.name.lowercased()
            let pathLower = candidate.path.lowercased()
            var score = 0
            if nameLower.hasPrefix(q) {
                score += 100
            } else if nameLower.contains(q) {
                score += 50
            } else if pathLower.contains(q) {
                score += 20
            } else {
                continue
            }
            // 짧은 이름 가산점 (정확한 매칭 우선)
            score += max(0, 50 - candidate.name.count)
            results.append(Match(path: candidate.path, name: candidate.name, score: score))
        }
        return results.sorted { $0.score > $1.score }
    }
}
