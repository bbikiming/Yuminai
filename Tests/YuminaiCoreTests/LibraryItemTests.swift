import Foundation
import Testing
@testable import YuminaiCore

@Suite("ResourceLibraryItem (ADR-111)")
struct LibraryItemTests {

    // MARK: - Codable round-trip

    @Test("Codable round-trip — community source 모든 필드 보존")
    func codableRoundTripCommunitySource() throws {
        let resourceId = UUID()
        let originalURL = URL(string: "https://raw.githubusercontent.com/test/repo/main/CLAUDE.md")!
        let item = ResourceLibraryItem(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            displayName: "테스트 자료",
            category: .claudeMd,
            source: .community(resourceId: resourceId, originalURL: originalURL),
            content: "# 테스트\n이 자료는 테스트용입니다.",
            tags: ["tdd", "swift"],
            addedAt: Date(timeIntervalSince1970: 1_700_000_000),
            notes: "메모"
        )

        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ResourceLibraryItem.self, from: data)

        #expect(decoded.id == item.id)
        #expect(decoded.displayName == item.displayName)
        #expect(decoded.category == item.category)
        #expect(decoded.content == item.content)
        #expect(decoded.tags == item.tags)
        #expect(decoded.notes == item.notes)

        if case .community(let rid, let url) = decoded.source {
            #expect(rid == resourceId)
            #expect(url == originalURL)
        } else {
            Issue.record("source가 .community가 아님")
        }
    }

    @Test("Codable round-trip — userImport source 보존")
    func codableRoundTripUserImportSource() throws {
        let importURL = URL(string: "https://example.com/my-rules.md")!
        let item = ResourceLibraryItem(
            displayName: "내 규칙",
            category: .skill,
            source: .userImport(originalURL: importURL),
            content: "# My Rules"
        )

        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ResourceLibraryItem.self, from: data)

        if case .userImport(let url) = decoded.source {
            #expect(url == importURL)
        } else {
            Issue.record("source가 .userImport가 아님")
        }
    }

    @Test("Codable round-trip — userText source 보존")
    func codableRoundTripUserTextSource() throws {
        let item = ResourceLibraryItem(
            displayName: "직접 입력 자료",
            category: .template,
            source: .userText,
            content: "내용"
        )

        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ResourceLibraryItem.self, from: data)

        if case .userText = decoded.source {
            // 정상
        } else {
            Issue.record("source가 .userText가 아님")
        }
    }

    // MARK: - byteSize

    @Test("byteSize — UTF-8 byte 수 반환")
    func byteSize() {
        let content = "Hello, World!"  // 13 bytes in UTF-8
        let item = ResourceLibraryItem(
            displayName: "test",
            category: .claudeMd,
            source: .userText,
            content: content
        )
        #expect(item.byteSize == 13)
    }

    @Test("byteSize — 빈 content면 0")
    func byteSizeEmpty() {
        let item = ResourceLibraryItem(
            displayName: "empty",
            category: .claudeMd,
            source: .userText,
            content: ""
        )
        #expect(item.byteSize == 0)
    }

    @Test("byteSize — 한글 멀티바이트 정확히 계산")
    func byteSizeKorean() {
        let content = "안녕"  // 각 3 bytes, 합계 6 bytes
        let item = ResourceLibraryItem(
            displayName: "korean",
            category: .claudeMd,
            source: .userText,
            content: content
        )
        #expect(item.byteSize == 6)
    }

    // MARK: - byteSizeDisplay

    @Test("byteSizeDisplay — 1023 bytes는 'B' 단위")
    func byteSizeDisplayBytes() {
        let item = ResourceLibraryItem(
            displayName: "test",
            category: .claudeMd,
            source: .userText,
            content: String(repeating: "A", count: 512)
        )
        #expect(item.byteSizeDisplay.hasSuffix("B"))
        #expect(!item.byteSizeDisplay.contains("K"))
    }

    @Test("byteSizeDisplay — 1024 bytes 이상은 'KB' 단위")
    func byteSizeDisplayKB() {
        let item = ResourceLibraryItem(
            displayName: "test",
            category: .claudeMd,
            source: .userText,
            content: String(repeating: "A", count: 1024)
        )
        #expect(item.byteSizeDisplay.contains("KB"))
    }

    // MARK: - addedAt 기본값

    @Test("addedAt — 기본값은 현재 시각 근처")
    func addedAtDefault() {
        let before = Date()
        let item = ResourceLibraryItem(
            displayName: "test",
            category: .claudeMd,
            source: .userText,
            content: "content"
        )
        let after = Date()
        #expect(item.addedAt >= before)
        #expect(item.addedAt <= after)
    }

    // MARK: - Source displayLabel + iconName

    @Test("Source.community — displayLabel과 iconName 비어있지 않음")
    func communitySourceLabels() {
        let source = ResourceLibraryItem.Source.community(resourceId: UUID(), originalURL: nil)
        #expect(!source.displayLabel.isEmpty)
        #expect(!source.iconName.isEmpty)
    }

    @Test("Source.userImport — displayLabel과 iconName 비어있지 않음")
    func userImportSourceLabels() {
        let source = ResourceLibraryItem.Source.userImport(originalURL: URL(string: "https://example.com/file.md")!)
        #expect(!source.displayLabel.isEmpty)
        #expect(!source.iconName.isEmpty)
    }

    @Test("Source.userText — displayLabel과 iconName 비어있지 않음")
    func userTextSourceLabels() {
        let source = ResourceLibraryItem.Source.userText
        #expect(!source.displayLabel.isEmpty)
        #expect(!source.iconName.isEmpty)
    }

    // MARK: - Hashable + Identifiable (id 기반)

    @Test("같은 id면 Hashable Set에서 하나로 처리")
    func hashableSet() {
        let id = UUID()
        let a = ResourceLibraryItem(id: id, displayName: "A", category: .claudeMd, source: .userText, content: "aaa")
        let b = ResourceLibraryItem(id: id, displayName: "B", category: .skill, source: .userText, content: "bbb")
        let set = Set([a, b])
        #expect(set.count == 1)
    }

    @Test("다른 id면 Hashable Set에서 별도 처리")
    func hashableSetDifferentIds() {
        let a = ResourceLibraryItem(displayName: "A", category: .claudeMd, source: .userText, content: "aaa")
        let b = ResourceLibraryItem(displayName: "B", category: .claudeMd, source: .userText, content: "bbb")
        let set = Set([a, b])
        #expect(set.count == 2)
    }

    // MARK: - LibraryItemError

    @Test("LibraryItemError.noRawURL — errorDescription 비어있지 않음")
    func errorNoRawURL() {
        let err = LibraryItemError.noRawURL
        #expect(!(err.errorDescription ?? "").isEmpty)
    }

    @Test("LibraryItemError.httpError — errorDescription에 URL 포함")
    func errorHttpError() {
        let url = URL(string: "https://example.com/file.md")!
        let err = LibraryItemError.httpError(url, 404)
        let desc = err.errorDescription ?? ""
        #expect(!desc.isEmpty)
        #expect(desc.contains("404") || desc.contains("URL"))
    }

    @Test("LibraryItemError.encodingError — errorDescription 비어있지 않음")
    func errorEncodingError() {
        let url = URL(string: "https://example.com/binary.bin")!
        let err = LibraryItemError.encodingError(url)
        #expect(!(err.errorDescription ?? "").isEmpty)
    }
}

// MARK: - AppPreferences 라이브러리 backward-compat 테스트

@Suite("AppPreferences libraryItems (ADR-111)")
struct AppPreferencesLibraryTests {

    @Test("기존 JSON에 libraryItems 없으면 빈 배열로 decode")
    func backwardCompatDecodeEmpty() throws {
        // libraryItems 필드가 없는 최소 JSON — 기존 사용자 데이터 시뮬레이션
        let minimalJSON = """
        {
          "claudeBinaryPath": "/usr/local/bin/claude"
        }
        """.data(using: .utf8)!

        let prefs = try JSONDecoder().decode(AppPreferences.self, from: minimalJSON)
        #expect(prefs.libraryItems.isEmpty)
    }

    @Test("libraryItems 필드가 있으면 정상 decode")
    func decodeWithLibraryItems() throws {
        let item = ResourceLibraryItem(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
            displayName: "테스트",
            category: .claudeMd,
            source: .userText,
            content: "# Test"
        )
        var prefs = AppPreferences()
        prefs.libraryItems = [item]
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: data)
        #expect(decoded.libraryItems.count == 1)
        #expect(decoded.libraryItems[0].displayName == "테스트")
    }
}
