import Foundation

/// 워크스페이스 디렉토리의 파일 시스템 트리 (ADR-037 D1).
///
/// **참조**: `ObsidianVault.tree()` 패턴 차용. 차이점: 일반 디렉토리 + .gitignore-like 제외.
///
/// 무거운 디렉토리 자동 제외 (`node_modules`, `.git`, `.build` 등).
/// 텍스트 파일만 표시 (binary는 hide). 사용자가 이 트리에서 파일을 선택해 viewer/editor로 본다.
public actor WorkspaceFileTree {
    public nonisolated let rootURL: URL

    /// 자동 제외 디렉토리 — 무거움 또는 소음.
    public static let excludedFolders: Set<String> = [
        ".git", ".svn", ".hg",
        "node_modules", "vendor", ".bundle",
        ".build", "target", "dist", "build", "out",
        ".next", ".nuxt", ".astro", ".cache",
        "__pycache__", ".venv", "venv", ".tox", ".pytest_cache",
        ".idea", ".vscode", ".cursor",
        "DerivedData", ".swiftpm",
        ".DS_Store"
    ]

    /// binary로 추정되는 확장자 — viewer에 안 좋음.
    public static let binaryExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "ico", "icns", "heic",
        "mp3", "mp4", "mov", "wav", "ogg",
        "zip", "tar", "gz", "tgz", "bz2", "7z",
        "pdf", "psd", "sketch",
        "ttf", "otf", "woff", "woff2",
        "exe", "dll", "so", "dylib", "a", "o",
        "class", "jar", "pyc"
    ]

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    public var isValid: Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }

    /// 트리 구성 — 폴더 + 텍스트 파일만, 자동 제외 디렉토리 hide.
    public func tree(maxDepth: Int = 6) async throws -> [FileNode] {
        guard isValid else {
            throw FileTreeError.notFound(path: rootURL.path)
        }
        return try buildNodes(at: rootURL, relativeTo: rootURL, depth: 0, maxDepth: maxDepth)
    }

    /// 단일 파일 본문 read (text only — 너무 크면 reject).
    public func read(_ relativePath: String, maxBytes: Int = 1_000_000) async throws -> String {
        let url = rootURL.appending(path: relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FileTreeError.fileNotFound(path: relativePath)
        }
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attrs[.size] as? Int, size > maxBytes {
            throw FileTreeError.tooLarge(path: relativePath, size: size, limit: maxBytes)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// 단일 파일 write — 디렉토리 자동 생성.
    public func write(_ relativePath: String, contents: String) async throws {
        let url = rootURL.appending(path: relativePath)
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Private

    private func buildNodes(at folder: URL, relativeTo root: URL, depth: Int, maxDepth: Int) throws -> [FileNode] {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        var nodes: [FileNode] = []
        for url in contents {
            let name = url.lastPathComponent
            // 자동 제외
            if Self.excludedFolders.contains(name) { continue }
            // hidden은 SkipsHiddenFiles로 이미 제외됐지만 일부 OS 차이 대비
            if name.hasPrefix(".") && name != ".env" && name != ".gitignore" { continue }

            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let relPath = relativePath(of: url, from: root)

            if isDir {
                if depth >= maxDepth {
                    // depth limit — 빈 폴더로 표시
                    nodes.append(.folder(name: name, path: relPath, children: []))
                } else {
                    let children = try buildNodes(at: url, relativeTo: root, depth: depth + 1, maxDepth: maxDepth)
                    nodes.append(.folder(name: name, path: relPath, children: children))
                }
            } else {
                let ext = url.pathExtension.lowercased()
                // binary는 표시는 하되 viewer 비활성 (UI에서 결정)
                let isBinary = Self.binaryExtensions.contains(ext)
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                nodes.append(.file(name: name, path: relPath, ext: ext, size: size, isBinary: isBinary))
            }
        }

        return nodes.sorted { lhs, rhs in
            switch (lhs, rhs) {
            case (.folder, .file): return true
            case (.file, .folder): return false
            default: return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
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
}

// MARK: - Models

public enum FileNode: Sendable, Identifiable, Equatable, Hashable {
    case folder(name: String, path: String, children: [FileNode])
    case file(name: String, path: String, ext: String, size: Int, isBinary: Bool)

    public var id: String { path }

    public var name: String {
        switch self {
        case .folder(let n, _, _): return n
        case .file(let n, _, _, _, _): return n
        }
    }

    public var path: String {
        switch self {
        case .folder(_, let p, _): return p
        case .file(_, let p, _, _, _): return p
        }
    }

    public var isFolder: Bool {
        if case .folder = self { return true }
        return false
    }

    public var isBinary: Bool {
        if case .file(_, _, _, _, let b) = self { return b }
        return false
    }
}

public enum FileTreeError: Error, LocalizedError, Sendable {
    case notFound(path: String)
    case fileNotFound(path: String)
    case tooLarge(path: String, size: Int, limit: Int)

    public var errorDescription: String? {
        switch self {
        case .notFound(let p): return "워크스페이스를 찾을 수 없어요: \(p)"
        case .fileNotFound(let p): return "파일을 찾을 수 없어요: \(p)"
        case .tooLarge(let p, let size, let limit):
            let mb = Double(size) / (1024 * 1024)
            return "파일이 너무 커요 (\(String(format: "%.1f", mb))MB > \(limit / 1_000_000)MB): \(p)"
        }
    }
}
