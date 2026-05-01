import Foundation
import AppKit
import YuminaiCore

/// Obsidian Vault 파일 시스템 어댑터.
///
/// `.md` 파일과 폴더 트리를 인덱싱하고, 노트 본문을 읽고, 검색을 제공한다.
/// Obsidian 앱과의 동기화는 별도 — `obsidian://` URL scheme로만 trigger.
public actor ObsidianVault {
    public nonisolated let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    /// Vault root가 실제 존재하고 디렉토리인지.
    public var isValid: Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }

    /// Vault 트리 구성. `.md` 파일과 폴더만 (숨김/`.obsidian` 제외).
    public func tree() async throws -> [VaultNode] {
        guard isValid else {
            throw VaultError.notFound(path: rootURL.path)
        }
        return try buildNodes(at: rootURL, relativeTo: rootURL)
    }

    /// 단일 노트 읽기. relativePath는 vault root 기준.
    public func read(_ relativePath: String) async throws -> Note {
        let url = rootURL.appending(path: relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VaultError.noteNotFound(path: relativePath)
        }
        let raw = try String(contentsOf: url, encoding: .utf8)
        let (frontmatter, body) = Self.splitFrontmatter(raw)
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let mtime = (attrs?[.modificationDate] as? Date) ?? Date()
        let title = url.deletingPathExtension().lastPathComponent

        return Note(
            path: relativePath,
            title: title,
            body: body,
            frontmatter: frontmatter,
            lastModified: mtime
        )
    }

    /// 단순 파일명 매칭 검색.
    public func search(query: String) async throws -> [VaultNode] {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let allNotes = try collectNotes(at: rootURL, relativeTo: rootURL)
        return allNotes.filter { node in
            if case .note(let name, _, _) = node {
                return name.lowercased().contains(q)
            }
            return false
        }
    }

    /// 파일명 + 본문 매칭. 큰 Vault는 비싸므로 limit 제한 + lazy.
    public func searchFullText(_ query: String, limit: Int = 50) async throws -> [SearchHit] {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        let allNotes = try collectNotes(at: rootURL, relativeTo: rootURL)
        var hits: [SearchHit] = []

        for case .note(let name, let path, _) in allNotes {
            if hits.count >= limit { break }

            // 파일명 매칭 우선
            if name.lowercased().contains(q) {
                hits.append(SearchHit(path: path, title: name, matchedLine: nil, matchSource: .filename))
                continue
            }

            // 본문 매칭
            let url = rootURL.appending(path: path)
            guard let body = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let bodyLower = body.lowercased()
            if let range = bodyLower.range(of: q) {
                let line = Self.contextSnippet(body: body, around: range, padding: 30)
                hits.append(SearchHit(path: path, title: name, matchedLine: line, matchSource: .body))
            }
        }

        return hits
    }

    /// 매칭된 위치 주변 컨텍스트 추출.
    static func contextSnippet(body: String, around range: Range<String.Index>, padding: Int) -> String {
        let bodyLower = body.lowercased()
        let lower = bodyLower.distance(from: bodyLower.startIndex, to: range.lowerBound)
        let upper = bodyLower.distance(from: bodyLower.startIndex, to: range.upperBound)
        let startOffset = max(0, lower - padding)
        let endOffset = min(body.count, upper + padding)
        let startIdx = body.index(body.startIndex, offsetBy: startOffset)
        let endIdx = body.index(body.startIndex, offsetBy: endOffset)
        var snippet = String(body[startIdx..<endIdx])
        snippet = snippet.replacingOccurrences(of: "\n", with: " ")
        if startOffset > 0 { snippet = "…" + snippet }
        if endOffset < body.count { snippet += "…" }
        return snippet
    }

    /// 노트 본문 저장 (편집 모드용).
    public func write(_ relativePath: String, content: String) async throws {
        let url = rootURL.appending(path: relativePath)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Obsidian 앱에서 노트 열기 (URL scheme).
    public nonisolated func openInObsidian(relativePath: String, vaultName: String? = nil) {
        let resolvedVault = vaultName ?? rootURL.lastPathComponent
        var components = URLComponents()
        components.scheme = "obsidian"
        components.host = "open"
        components.queryItems = [
            URLQueryItem(name: "vault", value: resolvedVault),
            URLQueryItem(name: "file", value: relativePath)
        ]
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Private

    private func buildNodes(at folder: URL, relativeTo root: URL) throws -> [VaultNode] {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        var nodes: [VaultNode] = []
        for url in contents {
            let name = url.lastPathComponent
            // Obsidian 메타 폴더 제외
            if name == ".obsidian" || name == ".trash" { continue }

            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let relPath = relativePath(of: url, from: root)

            if isDir {
                let children = try buildNodes(at: url, relativeTo: root)
                if !children.isEmpty {
                    nodes.append(.folder(name: name, path: relPath, children: children))
                }
            } else if url.pathExtension.lowercased() == "md" {
                let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
                let title = url.deletingPathExtension().lastPathComponent
                nodes.append(.note(name: title, path: relPath, lastModified: mtime))
            }
        }
        return nodes.sorted { lhs, rhs in
            // 폴더 먼저, 그 안에서 알파벳
            switch (lhs, rhs) {
            case (.folder, .note): return true
            case (.note, .folder): return false
            default: return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
    }

    private func collectNotes(at folder: URL, relativeTo root: URL) throws -> [VaultNode] {
        let nodes = try buildNodes(at: folder, relativeTo: root)
        var flat: [VaultNode] = []
        for node in nodes {
            switch node {
            case .note: flat.append(node)
            case .folder(_, _, let children):
                flat.append(contentsOf: flatten(children))
            }
        }
        return flat
    }

    private func flatten(_ nodes: [VaultNode]) -> [VaultNode] {
        nodes.flatMap { node -> [VaultNode] in
            switch node {
            case .note: return [node]
            case .folder(_, _, let children): return flatten(children)
            }
        }
    }

    private func relativePath(of url: URL, from root: URL) -> String {
        let full = url.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        if full.hasPrefix(rootPath) {
            let suffix = full.dropFirst(rootPath.count)
            return String(suffix.drop(while: { $0 == "/" }))
        }
        return url.lastPathComponent
    }

    /// `---\nkey: value\n---` 형식 frontmatter를 분리.
    static func splitFrontmatter(_ raw: String) -> ([String: String], String) {
        guard raw.hasPrefix("---\n") else { return ([:], raw) }
        let body = String(raw.dropFirst(4))
        guard let endRange = body.range(of: "\n---\n") else { return ([:], raw) }
        let yaml = String(body[..<endRange.lowerBound])
        let after = String(body[endRange.upperBound...])

        var dict: [String: String] = [:]
        for line in yaml.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 {
                let k = String(parts[0]).trimmingCharacters(in: .whitespaces)
                let v = String(parts[1]).trimmingCharacters(in: .whitespaces)
                dict[k] = v
            }
        }
        return (dict, after)
    }
}

// MARK: - Models

public enum VaultNode: Sendable, Identifiable, Equatable {
    case folder(name: String, path: String, children: [VaultNode])
    case note(name: String, path: String, lastModified: Date)

    public var id: String { path }

    public var name: String {
        switch self {
        case .folder(let n, _, _), .note(let n, _, _): return n
        }
    }

    public var path: String {
        switch self {
        case .folder(_, let p, _), .note(_, let p, _): return p
        }
    }

    public var isFolder: Bool {
        if case .folder = self { return true }
        return false
    }
}

public struct Note: Sendable, Equatable {
    public let path: String
    public let title: String
    public let body: String
    public let frontmatter: [String: String]
    public let lastModified: Date

    public init(
        path: String,
        title: String,
        body: String,
        frontmatter: [String: String] = [:],
        lastModified: Date = Date()
    ) {
        self.path = path
        self.title = title
        self.body = body
        self.frontmatter = frontmatter
        self.lastModified = lastModified
    }
}

public enum VaultError: Error, LocalizedError, Sendable {
    case notFound(path: String)
    case noteNotFound(path: String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let path):
            return "Vault 폴더를 찾을 수 없어요: \(path)"
        case .noteNotFound(let path):
            return "노트를 찾을 수 없어요: \(path)"
        }
    }
}

// MARK: - Search

public struct SearchHit: Sendable, Identifiable, Equatable {
    public let path: String
    public let title: String
    public let matchedLine: String?
    public let matchSource: MatchSource

    public var id: String { path }

    public init(path: String, title: String, matchedLine: String? = nil, matchSource: MatchSource = .filename) {
        self.path = path
        self.title = title
        self.matchedLine = matchedLine
        self.matchSource = matchSource
    }
}

public enum MatchSource: String, Sendable, Equatable {
    case filename, body
}
