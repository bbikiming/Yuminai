import Foundation
import Testing
@testable import YuminaiCore

@Suite("SmartFolder (ADR-077 Phase 3)")
struct SmartFolderTests {

    @Test("SmartFolderKind allCases — 3개")
    func allCases() {
        #expect(SmartFolderKind.allCases.count == 3)
        #expect(SmartFolderKind.allCases.contains(.recentWeek))
        #expect(SmartFolderKind.allCases.contains(.telegramBound))
        #expect(SmartFolderKind.allCases.contains(.archived))
    }

    @Test("displayName 한국어")
    func displayNames() {
        #expect(SmartFolderKind.recentWeek.displayName == "최근 7일")
        #expect(SmartFolderKind.telegramBound.displayName == "텔레그램 연결됨")
        #expect(SmartFolderKind.archived.displayName == "보관함")
    }

    @Test("default 활성화 — recentWeek만")
    func defaultEnabled() {
        let defaults = SmartFolderKind.defaultEnabled
        #expect(defaults.contains(.recentWeek))
        #expect(defaults.count == 1)
    }

    @Test("Codable round-trip")
    func roundTrip() throws {
        let original: Set<SmartFolderKind> = [.recentWeek, .telegramBound]
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Set<SmartFolderKind>.self, from: encoded)
        #expect(decoded == original)
    }
}

@Suite("SmartFolderEvaluator")
struct SmartFolderEvaluatorTests {

    @Test("isRecent — nil은 false")
    func recentNil() {
        #expect(SmartFolderEvaluator.isRecent(lastOpenedAt: nil) == false)
    }

    @Test("isRecent — 7일 안")
    func recentInside() {
        let now = Date()
        let yesterday = now.addingTimeInterval(-1 * 24 * 60 * 60)
        let sixDaysAgo = now.addingTimeInterval(-6 * 24 * 60 * 60)
        #expect(SmartFolderEvaluator.isRecent(lastOpenedAt: yesterday, now: now) == true)
        #expect(SmartFolderEvaluator.isRecent(lastOpenedAt: sixDaysAgo, now: now) == true)
    }

    @Test("isRecent — 7일 초과는 false")
    func recentOutside() {
        let now = Date()
        let eightDaysAgo = now.addingTimeInterval(-8 * 24 * 60 * 60)
        let monthAgo = now.addingTimeInterval(-30 * 24 * 60 * 60)
        #expect(SmartFolderEvaluator.isRecent(lastOpenedAt: eightDaysAgo, now: now) == false)
        #expect(SmartFolderEvaluator.isRecent(lastOpenedAt: monthAgo, now: now) == false)
    }

    @Test("isTelegramBound — boundId 일치")
    func telegramBoundLegacy() {
        let id = UUID()
        let other = UUID()
        #expect(SmartFolderEvaluator.isTelegramBound(workspaceId: id, boundId: id, chatBindings: [:]) == true)
        #expect(SmartFolderEvaluator.isTelegramBound(workspaceId: other, boundId: id, chatBindings: [:]) == false)
    }

    @Test("isTelegramBound — chatBindings에 포함")
    func telegramBoundChatBinding() {
        let id = UUID()
        let bindings = ["chat-1": id]
        #expect(SmartFolderEvaluator.isTelegramBound(workspaceId: id, boundId: nil, chatBindings: bindings) == true)
    }

    @Test("isTelegramBound — 둘 다 매칭 안 됨")
    func telegramBoundNone() {
        let id = UUID()
        #expect(SmartFolderEvaluator.isTelegramBound(workspaceId: id, boundId: nil, chatBindings: [:]) == false)
    }
}

@Suite("FolderColorPreset / FolderIconPreset (ADR-077 Phase 2)")
struct FolderPresetTests {

    @Test("FolderColorPreset — 10개 색상")
    func colorCount() {
        #expect(FolderColorPreset.allCases.count == 10)
    }

    @Test("FolderIconPreset — 12개 아이콘")
    func iconCount() {
        #expect(FolderIconPreset.allCases.count == 12)
    }

    @Test("FolderColorPreset.accent default — 호환")
    func accentDefault() {
        #expect(FolderColorPreset.accent.rawValue == "accent")
    }

    @Test("FolderIconPreset.folderFill default")
    func folderFillDefault() {
        #expect(FolderIconPreset.folderFill.rawValue == "folder.fill")
    }

    @Test("Identifiable conformance — id == rawValue")
    func identifiable() {
        for color in FolderColorPreset.allCases {
            #expect(color.id == color.rawValue)
        }
        for icon in FolderIconPreset.allCases {
            #expect(icon.id == icon.rawValue)
        }
    }

    @Test("displayName 한국어 (모든 case)")
    func koreanDisplayNames() {
        // 모두 한국어 라벨이 있어야 함
        for color in FolderColorPreset.allCases {
            #expect(!color.displayName.isEmpty)
        }
        for icon in FolderIconPreset.allCases {
            #expect(!icon.displayName.isEmpty)
        }
    }
}

@Suite("WorkspaceFolder colorName (ADR-077 Phase 2)")
struct WorkspaceFolderColorTests {

    @Test("default colorName — accent")
    func defaultColor() {
        let folder = WorkspaceFolder(name: "test")
        #expect(folder.colorName == "accent")
    }

    @Test("custom colorName 지정")
    func customColor() {
        let folder = WorkspaceFolder(name: "test", colorName: "purple")
        #expect(folder.colorName == "purple")
    }

    @Test("Codable backward-compat — colorName 없는 JSON")
    func backwardCompatColor() throws {
        let oldJSON = """
        {
            "id": "12345678-1234-1234-1234-123456789012",
            "name": "구버전",
            "workspaceIds": [],
            "isExpanded": true,
            "iconName": "folder.fill"
        }
        """.data(using: .utf8)!
        let folder = try JSONDecoder().decode(WorkspaceFolder.self, from: oldJSON)
        #expect(folder.colorName == "accent")  // default
    }

    @Test("Codable round-trip with color + icon")
    func roundTripWithCustomization() throws {
        let original = WorkspaceFolder(
            name: "프로젝트",
            iconName: "briefcase.fill",
            colorName: "purple"
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorkspaceFolder.self, from: encoded)
        #expect(decoded.iconName == "briefcase.fill")
        #expect(decoded.colorName == "purple")
    }
}
