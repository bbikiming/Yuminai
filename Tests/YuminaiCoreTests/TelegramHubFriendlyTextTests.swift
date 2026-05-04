import XCTest
@testable import YuminaiCore

/// **ADR-101** — TelegramHubFriendlyText 단위 테스트.
/// 각 enum case / static property가 의미 있는 비어있지 않은 문자열로 매핑됐는지 검증.
final class TelegramHubFriendlyTextTests: XCTestCase {

    // MARK: - Tab 라벨

    func test_tabLabels_areNotEmpty() {
        XCTAssertFalse(TelegramHubFriendlyText.Tab.bots.isEmpty)
        XCTAssertFalse(TelegramHubFriendlyText.Tab.bindings.isEmpty)
        XCTAssertFalse(TelegramHubFriendlyText.Tab.commands.isEmpty)
        XCTAssertFalse(TelegramHubFriendlyText.Tab.activity.isEmpty)
        XCTAssertFalse(TelegramHubFriendlyText.Tab.settings.isEmpty)
    }

    func test_tabLabels_allDifferent() {
        let labels = [
            TelegramHubFriendlyText.Tab.bots,
            TelegramHubFriendlyText.Tab.bindings,
            TelegramHubFriendlyText.Tab.commands,
            TelegramHubFriendlyText.Tab.activity,
            TelegramHubFriendlyText.Tab.settings
        ]
        XCTAssertEqual(Set(labels).count, labels.count, "탭 라벨이 중복되면 안 됩니다")
    }

    // MARK: - chatType(for:)

    func test_chatType_positiveId_isPrivateLabel() {
        XCTAssertEqual(TelegramHubFriendlyText.chatType(for: 123), "1:1 대화")
    }

    func test_chatType_negativeId_isGroupLabel() {
        XCTAssertEqual(TelegramHubFriendlyText.chatType(for: -123), "그룹 채팅")
    }

    func test_chatTypeHelp_positive_containsPrivateKeyword() {
        let help = TelegramHubFriendlyText.chatTypeHelp(for: 123)
        XCTAssertFalse(help.isEmpty)
        XCTAssertTrue(help.contains("1:1"))
    }

    func test_chatTypeHelp_negative_containsGroupKeyword() {
        let help = TelegramHubFriendlyText.chatTypeHelp(for: -100)
        XCTAssertFalse(help.isEmpty)
        XCTAssertTrue(help.contains("단체") || help.contains("그룹"))
    }

    // MARK: - DeviceStateLabel

    func test_deviceStateLabel_allCasesHaveLabels() {
        let cases = ["desktopActive", "desktopIdle", "desktopOff"]
        for caseName in cases {
            let label = TelegramHubFriendlyText.DeviceStateLabel.label(for: caseName)
            XCTAssertFalse(label.isEmpty, "DeviceState '\(caseName)' 라벨이 비어있음")
            // fallback은 원본 caseName 그대로 — 위의 3 케이스는 번역된 라벨이 있어야 함
            XCTAssertNotEqual(label, caseName, "DeviceState '\(caseName)'이 번역되지 않음")
        }
    }

    // MARK: - NotificationKindLabel

    func test_notificationKindLabel_allCasesHaveLabels() {
        let cases = [
            "hitlApprovalRequest",
            "taskCompleteSuccess",
            "taskCompleteFailure",
            "rateLimitAlert",
            "generalAlert"
        ]
        for caseName in cases {
            let label = TelegramHubFriendlyText.NotificationKindLabel.label(for: caseName)
            XCTAssertFalse(label.isEmpty, "NotificationKind '\(caseName)' 라벨이 비어있음")
            XCTAssertNotEqual(label, caseName, "NotificationKind '\(caseName)'이 번역되지 않음")
        }
    }

    // MARK: - DeliveryChannelLabel

    func test_deliveryChannelLabel_allCasesHaveLabels() {
        let cases = ["macOSOnly", "telegramOnly", "both", "suppressed"]
        for caseName in cases {
            let full  = TelegramHubFriendlyText.DeliveryChannelLabel.label(for: caseName)
            let short = TelegramHubFriendlyText.DeliveryChannelLabel.shortLabel(for: caseName)
            XCTAssertFalse(full.isEmpty, "DeliveryChannel '\(caseName)' 라벨이 비어있음")
            XCTAssertFalse(short.isEmpty, "DeliveryChannel '\(caseName)' shortLabel이 비어있음")
        }
    }

    // MARK: - 일반 용어

    func test_generalTerms_areNotEmpty() {
        XCTAssertFalse(TelegramHubFriendlyText.binding.isEmpty)
        XCTAssertFalse(TelegramHubFriendlyText.chatId.isEmpty)
        XCTAssertFalse(TelegramHubFriendlyText.workspace.isEmpty)
        XCTAssertFalse(TelegramHubFriendlyText.whitelist.isEmpty)
        XCTAssertFalse(TelegramHubFriendlyText.hitl.isEmpty)
        XCTAssertFalse(TelegramHubFriendlyText.quietHours.isEmpty)
        XCTAssertFalse(TelegramHubFriendlyText.hitlTimeout.isEmpty)
        XCTAssertFalse(TelegramHubFriendlyText.diffPreviewLimit.isEmpty)
        XCTAssertFalse(TelegramHubFriendlyText.notificationMatrix.isEmpty)
    }

    // MARK: - chat type callout

    func test_chatTypeCallout_notEmpty() {
        XCTAssertFalse(TelegramHubFriendlyText.chatTypeCalloutTitle.isEmpty)
        XCTAssertFalse(TelegramHubFriendlyText.chatTypeCalloutBody.isEmpty)
    }

    // MARK: - 중복 봇

    func test_duplicateBotStrings_notEmpty() {
        XCTAssertFalse(TelegramHubFriendlyText.duplicateBotBadge.isEmpty)
        XCTAssertFalse(TelegramHubFriendlyText.duplicateBotCallout.isEmpty)
    }
}
