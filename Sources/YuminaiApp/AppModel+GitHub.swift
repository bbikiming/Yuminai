import Foundation
import os
import YuminaiCore
import YuminaiClaudeAdapter
import YuminaiPersistence
import YuminaiTelegram
import YuminaiHarness

// ADR-127 — AppModel.swift 분할: GitHub 도메인 (PAT + 검색 히스토리 + 커뮤니티 자료 적용)
extension AppModel {

    // MARK: - ADR-119 — GitHub PAT

    /// GitHub PAT를 Keychain에 저장하고 preferences 메타를 갱신한다.
    public func saveGitHubPAT(_ token: String) async throws {
        try await keychainStore.set(token, for: KeychainKey.githubPersonalAccessToken)
        githubPATStatus = .set
        preferences.hasGitHubPAT = true
        await savePreferences()
    }

    /// GitHub PAT를 Keychain에서 삭제하고 preferences 메타를 초기화한다.
    public func removeGitHubPAT() async {
        try? await keychainStore.remove(KeychainKey.githubPersonalAccessToken)
        githubPATStatus = .notSet
        preferences.hasGitHubPAT = false
        await savePreferences()
    }

    /// Keychain에서 GitHub PAT를 읽어 반환한다. 없으면 nil.
    public func loadGitHubPAT() async -> String? {
        try? await keychainStore.get(KeychainKey.githubPersonalAccessToken)
    }

    // MARK: - ADR-122 Phase 3 — 검색 히스토리 / 즐겨찾기

    /// 검색 히스토리에 항목 추가 (ring buffer 50개, 중복 제거).
    public func addSearchHistory(query: String, mode: GitHubSearchHistoryEntry.Mode, resultCount: Int) {
        let entry = GitHubSearchHistoryEntry(query: query, mode: mode, resultCount: resultCount)
        preferences = {
            var p = preferences
            p.githubSearchHistory = GitHubSearchHistoryBuffer.append(entry, to: p.githubSearchHistory)
            return p
        }()
        Task { await savePreferences() }
    }

    /// 검색 히스토리 전체 초기화.
    public func clearSearchHistory() {
        preferences = { var p = preferences; p.githubSearchHistory = []; return p }()
        Task { await savePreferences() }
    }

    /// 현재 검색어를 즐겨찾기에 저장.
    public func saveSearchAsFavorite(query: String, mode: GitHubSearchHistoryEntry.Mode, label: String) {
        let fav = GitHubSearchFavorite(query: query, mode: mode, label: label)
        preferences = { var p = preferences; p.githubSearchFavorites.append(fav); return p }()
        Task { await savePreferences() }
    }

    /// 즐겨찾기 항목 삭제.
    public func removeSearchFavorite(_ favorite: GitHubSearchFavorite) {
        preferences = {
            var p = preferences
            p.githubSearchFavorites = p.githubSearchFavorites.filter { $0.id != favorite.id }
            return p
        }()
        Task { await savePreferences() }
    }

    // MARK: - ADR-109 — 커뮤니티 자료 적용

    /// 커뮤니티 자료를 현재 워크스페이스에 적용한다.
    ///
    /// - `category == .claudeMd`: rawURL 다운로드 → CLAUDE.md에 마커 블록으로 삽입
    /// - `category == .skill`: `.harness/skills/<resource.id>.md`에 저장
    /// - `category == .template`: GitHub 안내 메시지 반환 (다운로드 없음)
    ///
    /// 사용자가 명시적으로 [적용] 버튼을 누를 때만 호출된다 (자동 다운로드 없음).
    /// 다운로드 전에 UI에서 URL과 내용을 먼저 표시한다.
    public func applyCommunityResource(
        _ resource: CommunityResource,
        to workspaceURL: URL
    ) async -> Result<String, Error> {
        switch resource.category {
        case .template:
            return .success("GitHub 리포지토리를 직접 클론하거나 다운로드하세요.")

        case .claudeMd, .styleGuide, .workflow, .architecture, .promptPattern, .rules,
             .webFramework, .mobileFramework, .graphics3D, .backend, .database, .devops,
             .githubAction, .gitlabCI, .prTemplate, .issueTemplate:
            guard let rawURL = resource.rawURL else {
                return .failure(CommunityResourceError.noRawURL)
            }
            return await downloadAndAppendToCLAUDEMd(rawURL: rawURL, resource: resource, workspaceURL: workspaceURL)

        case .skill, .mcp:
            guard let rawURL = resource.rawURL else {
                return .failure(CommunityResourceError.noRawURL)
            }
            return await downloadAndSaveSkill(rawURL: rawURL, resource: resource, workspaceURL: workspaceURL)
        }
    }

    private func downloadAndAppendToCLAUDEMd(
        rawURL: URL,
        resource: CommunityResource,
        workspaceURL: URL
    ) async -> Result<String, Error> {
        do {
            let content = try await downloadRawContent(from: rawURL)
            let mdURL = workspaceURL.appendingPathComponent("CLAUDE.md")
            let existing = try? String(contentsOf: mdURL, encoding: .utf8)

            let beginMarker = "<!-- BEGIN COMMUNITY: \(resource.id) -->"
            let endMarker = "<!-- END COMMUNITY: \(resource.id) -->"

            // 이미 적용된 경우 기존 블록 교체
            let block = "\(beginMarker)\n\(content.trimmingCharacters(in: .whitespacesAndNewlines))\n\(endMarker)"

            let merged: String
            if let existing {
                if existing.contains(beginMarker) {
                    // 기존 블록 교체
                    let pattern = "\(NSRegularExpression.escapedPattern(for: beginMarker)).*?\(NSRegularExpression.escapedPattern(for: endMarker))"
                    if let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) {
                        let range = NSRange(existing.startIndex..., in: existing)
                        merged = regex.stringByReplacingMatches(in: existing, range: range, withTemplate: block)
                    } else {
                        merged = existing + "\n\n" + block
                    }
                } else {
                    let separator = existing.hasSuffix("\n\n") ? "" : existing.hasSuffix("\n") ? "\n" : "\n\n"
                    merged = existing + separator + block
                }
            } else {
                merged = block
            }

            try merged.write(to: mdURL, atomically: true, encoding: .utf8)
            return .success("\(resource.displayName)를 CLAUDE.md에 추가했어요.")
        } catch {
            logger.error("커뮤니티 자료 CLAUDE.md 적용 실패: \(error.localizedDescription)")
            return .failure(error)
        }
    }

    private func downloadAndSaveSkill(
        rawURL: URL,
        resource: CommunityResource,
        workspaceURL: URL
    ) async -> Result<String, Error> {
        do {
            let content = try await downloadRawContent(from: rawURL)
            let layout = HarnessLayout(workspaceURL: workspaceURL)
            let fm = FileManager.default
            let skillsURL = layout.harnessURL.appendingPathComponent("skills", isDirectory: true)
            try fm.createDirectory(at: skillsURL, withIntermediateDirectories: true)
            let fileURL = skillsURL.appendingPathComponent("\(resource.id).md")
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return .success("\(resource.displayName) Skill을 .harness/skills/에 저장했어요.")
        } catch {
            logger.error("커뮤니티 자료 Skill 저장 실패: \(error.localizedDescription)")
            return .failure(error)
        }
    }

    /// URL에서 원본 텍스트를 다운로드한다.
    /// - timeout: 60s (큰 파일 대비 ADR-111).
    /// - 에러: CommunityResourceError (네트워크 / HTTP 4xx / HTTP 5xx / encoding).
    func downloadRawContent(from url: URL) async throws -> String {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60
        let session = URLSession(configuration: config)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw CommunityResourceError.networkError(error)
        }
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw CommunityResourceError.httpErrorWithURL(url, httpResponse.statusCode)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw CommunityResourceError.invalidEncoding
        }
        return text
    }
}
