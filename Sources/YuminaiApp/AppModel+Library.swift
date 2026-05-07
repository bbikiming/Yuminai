import Foundation
import os
import YuminaiCore
import YuminaiPersistence

// ADR-127 — AppModel.swift 분할: Library 도메인 (CRUD + 첨부파일 관리)
extension AppModel {

    // MARK: - ADR-111 라이브러리 관리

    /// 라이브러리 디렉토리 URL: `~/Library/Application Support/Yuminai/library/`
    private var libraryDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Yuminai/library", isDirectory: true)
    }

    /// 라이브러리 항목의 디스크 URL.
    private func libraryFileURL(for id: UUID) -> URL {
        libraryDirectoryURL.appendingPathComponent("\(id.uuidString).md")
    }

    /// 라이브러리 디렉토리를 생성한다 (없으면).
    private func ensureLibraryDirectory() throws {
        let fm = FileManager.default
        let dir = libraryDirectoryURL
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// 커뮤니티 자료 다운로드 → 라이브러리 추가.
    /// 다운로드 실패 시 명확한 에러 (URL + status + suggestion).
    public func addToLibraryFromCommunity(_ resource: CommunityResource) async -> Result<ResourceLibraryItem, Error> {
        guard let rawURL = resource.rawURL else {
            return .failure(LibraryItemError.noRawURL)
        }

        let content: String
        do {
            content = try await downloadRawContent(from: rawURL)
        } catch let err as CommunityResourceError {
            return .failure(err)
        } catch {
            return .failure(LibraryItemError.networkError(rawURL, error))
        }

        // 이미 라이브러리에 있으면 기존 항목 반환 (중복 방지)
        if let existing = preferences.libraryItems.first(where: { item in
            if case .community(let rid, _) = item.source { return rid == resource.id }
            return false
        }) {
            return .success(existing)
        }

        let item = ResourceLibraryItem(
            displayName: resource.displayName,
            category: resource.category,
            source: .community(resourceId: resource.id, originalURL: rawURL),
            content: content,
            tags: resource.tags
        )

        do {
            try ensureLibraryDirectory()
            let fileURL = libraryFileURL(for: item.id)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            return .failure(LibraryItemError.diskWriteError(libraryDirectoryURL, error))
        }

        preferences = { var p = preferences; p.libraryItems.append(item); return p }()
        await savePreferences()
        logger.info("라이브러리에 추가: \(item.displayName) [\(item.id)]")
        return .success(item)
    }

    /// **ADR-113** — 스택 번들의 모든 자료를 라이브러리에 추가.
    ///
    /// 번들의 `resourceIds`를 순회하며 `CommunityCatalog.curated`에서 자료를 찾아 다운로드한다.
    /// rawURL이 없거나 다운로드 실패한 자료는 건너뛰고 로그를 남긴다.
    /// - Returns: 성공적으로 추가된 항목 배열 (부분 성공 허용).
    public func addBundleToLibrary(_ bundle: StackBundle) async -> [ResourceLibraryItem] {
        let all = CommunityCatalog.curated
        var added: [ResourceLibraryItem] = []

        for resourceId in bundle.resourceIds {
            guard let resource = all.first(where: { $0.id == resourceId }) else {
                logger.warning("번들 자료 미발견: \(resourceId) [\(bundle.displayName)]")
                continue
            }
            guard resource.rawURL != nil else {
                logger.info("번들 자료 rawURL 없음 (건너뜀): \(resource.displayName)")
                continue
            }
            let result = await addToLibraryFromCommunity(resource)
            switch result {
            case .success(let item):
                added.append(item)
            case .failure(let err):
                logger.error("번들 자료 추가 실패: \(resource.displayName) — \(err.localizedDescription)")
            }
        }

        logger.info("번들 추가 완료: \(bundle.displayName) — \(added.count)/\(bundle.resourceIds.count)개 추가")
        return added
    }

    /// 사용자 직접 URL → 라이브러리 추가.
    public func addToLibraryFromURL(
        _ url: URL,
        displayName: String,
        category: CommunityResource.Category
    ) async -> Result<ResourceLibraryItem, Error> {
        let content: String
        do {
            content = try await downloadRawContent(from: url)
        } catch let err as CommunityResourceError {
            return .failure(err)
        } catch {
            return .failure(LibraryItemError.networkError(url, error))
        }

        let item = ResourceLibraryItem(
            displayName: displayName.isEmpty ? (url.lastPathComponent.isEmpty ? "자료" : url.lastPathComponent) : displayName,
            category: category,
            source: .userImport(originalURL: url),
            content: content,
            tags: []
        )

        do {
            try ensureLibraryDirectory()
            try content.write(to: libraryFileURL(for: item.id), atomically: true, encoding: .utf8)
        } catch {
            return .failure(LibraryItemError.diskWriteError(libraryDirectoryURL, error))
        }

        preferences = { var p = preferences; p.libraryItems.append(item); return p }()
        await savePreferences()
        return .success(item)
    }

    /// 사용자 직접 텍스트 입력 → 라이브러리 추가.
    public func addToLibraryFromText(
        _ content: String,
        displayName: String,
        category: CommunityResource.Category,
        tags: [String]
    ) async -> ResourceLibraryItem {
        let item = ResourceLibraryItem(
            displayName: displayName.isEmpty ? "사용자 자료" : displayName,
            category: category,
            source: .userText,
            content: content,
            tags: tags
        )

        if let _ = try? ensureLibraryDirectory() {}
        try? content.write(to: libraryFileURL(for: item.id), atomically: true, encoding: .utf8)

        preferences = { var p = preferences; p.libraryItems.append(item); return p }()
        await savePreferences()
        return item
    }

    /// 라이브러리 항목 삭제 (디스크 + preferences).
    public func removeLibraryItem(_ id: UUID) async {
        let fileURL = libraryFileURL(for: id)
        try? FileManager.default.removeItem(at: fileURL)
        preferences = { var p = preferences; p.libraryItems.removeAll { $0.id == id }; return p }()
        await savePreferences()
    }

    /// 라이브러리 항목 수정 (displayName / notes / tags).
    public func updateLibraryItem(_ item: ResourceLibraryItem) async {
        preferences = { var p = preferences
            if let idx = p.libraryItems.firstIndex(where: { $0.id == item.id }) {
                p.libraryItems[idx] = item
            }
            return p
        }()
        await savePreferences()
    }

    /// 라이브러리 항목 → 메시지 첨부용 파일 URL.
    /// 파일이 디스크에 없으면 재생성 후 반환.
    public func attachmentURL(for libraryItem: ResourceLibraryItem) async -> URL? {
        let fileURL = libraryFileURL(for: libraryItem.id)
        let fm = FileManager.default
        if !fm.fileExists(atPath: fileURL.path) {
            // 재생성 시도
            do {
                try ensureLibraryDirectory()
                try libraryItem.content.write(to: fileURL, atomically: true, encoding: .utf8)
            } catch {
                logger.error("라이브러리 첨부 파일 생성 실패: \(error.localizedDescription)")
                return nil
            }
        }
        return fileURL
    }

    /// 특정 CommunityResource가 이미 라이브러리에 있는지 확인.
    public func isInLibrary(_ resource: CommunityResource) -> Bool {
        preferences.libraryItems.contains { item in
            if case .community(let rid, _) = item.source { return rid == resource.id }
            return false
        }
    }

    // MARK: - ADR-111 라이브러리 첨부파일

    /// 라이브러리 항목을 Composer에 첨부.
    public func attachLibraryItem(_ item: ResourceLibraryItem) {
        guard !attachedLibraryItems.contains(item) else { return }
        attachedLibraryItems.append(item)
    }

    /// Composer에서 라이브러리 항목 첨부 제거.
    public func removeLibraryItemAttachment(_ item: ResourceLibraryItem) {
        attachedLibraryItems.removeAll { $0.id == item.id }
    }

    /// Composer 라이브러리 첨부 전체 제거.
    public func clearLibraryItemAttachments() {
        attachedLibraryItems = []
    }
}
