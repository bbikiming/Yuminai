import Foundation

/// **ADR-101** — Telegram Hub 친화 언어 사전.
///
/// 사용자에게 보이는 모든 UI 텍스트를 쉬운 한국어로 통일한다.
/// 코드 주석·내부 로직은 변경하지 않으며, UI 문자열만 이 파일에서 관리한다.
///
/// 사용법:
/// ```swift
/// Text(TelegramHubFriendlyText.Tab.bindings)   // "연결"
/// Text(TelegramHubFriendlyText.chatType(for: -123)) // "그룹 채팅"
/// ```
public enum TelegramHubFriendlyText {

    // MARK: - 탭 라벨

    public enum Tab {
        /// 봇 목록 탭
        public static let bots     = "봇 목록"
        /// 연결(binding) 탭
        public static let bindings = "연결"
        /// 명령어 탭
        public static let commands = "명령어"
        /// 활동 로그 탭
        public static let activity = "활동 로그"
        /// 설정 탭
        public static let settings = "설정"
    }

    // MARK: - Chat 타입

    /// chat id 부호로 1:1 대화 / 그룹 채팅을 구분.
    public static func chatType(for chatId: Int64) -> String {
        chatId < 0 ? "그룹 채팅" : "1:1 대화"
    }

    /// Chat 타입 아이콘 (SF Symbol).
    public static func chatTypeIcon(for chatId: Int64) -> String {
        chatId < 0 ? "person.3.fill" : "person.crop.circle.fill"
    }

    /// Chat 타입별 도움말 문구.
    public static func chatTypeHelp(for chatId: Int64) -> String {
        chatId < 0
            ? "여러 명이 함께 볼 수 있는 단체방. 명령을 보낸 사람이 누구든 봇이 응답합니다. 신뢰하는 멤버만 있는 방을 권장."
            : "나만 볼 수 있는 1:1 비공개 대화방. 가장 안전하고 추천."
    }

    // MARK: - 알림 정책

    public enum DeviceStateLabel {
        public static let active = "데스크탑 사용 중"
        public static let idle   = "잠시 자리 비움"
        public static let off    = "꺼짐"

        /// DeviceState case 이름으로 라벨 반환 (열거형에서 직접 접근 가능하도록 헬퍼).
        public static func label(for caseName: String) -> String {
            switch caseName {
            case "desktopActive": return active
            case "desktopIdle":   return idle
            case "desktopOff":    return off
            default:              return caseName
            }
        }
    }

    public enum NotificationKindLabel {
        public static let hitlApprovalRequest = "위험 명령 확인 요청"
        public static let taskCompleteSuccess = "작업 완료 (성공)"
        public static let taskCompleteFailure = "작업 실패"
        public static let rateLimitAlert      = "사용량 한도 경고"
        public static let generalAlert        = "일반 알림"

        public static func label(for caseName: String) -> String {
            switch caseName {
            case "hitlApprovalRequest": return hitlApprovalRequest
            case "taskCompleteSuccess": return taskCompleteSuccess
            case "taskCompleteFailure": return taskCompleteFailure
            case "rateLimitAlert":      return rateLimitAlert
            case "generalAlert":        return generalAlert
            default:                    return caseName
            }
        }
    }

    public enum DeliveryChannelLabel {
        public static let macOSOnly    = "데스크탑만"
        public static let telegramOnly = "텔레그램만"
        public static let both         = "둘 다"
        public static let suppressed   = "알림 끔"

        public static let macOSOnlyShort    = "데스크탑"
        public static let telegramOnlyShort = "텔레그램"
        public static let bothShort         = "둘 다"
        public static let suppressedShort   = "끔"

        public static func label(for caseName: String) -> String {
            switch caseName {
            case "macOSOnly":    return macOSOnly
            case "telegramOnly": return telegramOnly
            case "both":         return both
            case "suppressed":   return suppressed
            default:             return caseName
            }
        }

        public static func shortLabel(for caseName: String) -> String {
            switch caseName {
            case "macOSOnly":    return macOSOnlyShort
            case "telegramOnly": return telegramOnlyShort
            case "both":         return bothShort
            case "suppressed":   return suppressedShort
            default:             return caseName
            }
        }
    }

    // MARK: - 일반 용어

    /// "binding" → "연결 설정"
    public static let binding           = "연결 설정"
    /// "Bindings" (복수) → "연결"
    public static let bindings          = "연결"
    /// "Chat ID" → "대화방 번호"
    public static let chatId            = "대화방 번호"
    /// "workspace" → "작업 폴더"
    public static let workspace         = "작업 폴더"
    /// "whitelist" → "접근 허가 목록"
    public static let whitelist         = "접근 허가 목록"
    /// "allowedUserIds" → "사용 가능한 사람"
    public static let allowedUserIds    = "사용 가능한 사람"
    /// "HITL" → "위험 명령 확인"
    public static let hitl              = "위험 명령 확인"
    /// "polling" → "자동으로 새 메시지 받기"
    public static let polling           = "자동으로 새 메시지 받기"
    /// "setMyCommands / sync to BotFather" → "텔레그램 봇 명령 메뉴 등록"
    public static let setMyCommands     = "텔레그램 봇 명령 메뉴 등록"
    /// "ephemeral" → "임시"
    public static let ephemeral         = "임시"
    /// "Quiet Hours" → "방해 금지 시간"
    public static let quietHours        = "방해 금지 시간"
    /// "HITL timeout" → "확인 대기 시간"
    public static let hitlTimeout       = "확인 대기 시간"
    /// "Diff preview line limit" → "변경사항 미리보기 줄 수"
    public static let diffPreviewLimit  = "변경사항 미리보기 줄 수"
    /// "Notification Policy Matrix" → "알림 정책 표"
    public static let notificationMatrix = "알림 정책 표"
    /// keychainKey 보조 설명
    public static let keychainKeyHint   = "macOS 비밀번호 저장소 키"
    /// Token 보조 설명
    public static let tokenHint         = "BotFather에서 받은 봇 비밀번호"

    // MARK: - Chat 타입 안내 문구 (inline callout)

    /// CokacdirImportSheet / Onboarding Step 3 상단에 두 chat 타입 차이를 설명하는 문구.
    public static let chatTypeCalloutTitle = "대화방 종류 안내"
    public static let chatTypeCalloutBody  = """
        • 1:1 대화 (번호 > 0): 나만 볼 수 있는 비공개 대화방. 가장 안전하고 추천합니다.
        • 그룹 채팅 (번호 < 0): 여러 명이 함께 볼 수 있는 단체방. 신뢰하는 멤버만 있는 방을 권장합니다.
        """

    // MARK: - 중복 봇 안내

    public static let duplicateBotBadge   = "이미 등록됨"
    public static let duplicateBotCallout = "이 봇은 이미 Telegram Hub에 등록되어 있어요. 등록된 봇을 보려면 봇 목록 탭을 확인하세요."

    // MARK: - Whitelist (ADR-101 친화 언어 / ADR-126)

    /// **ADR-126** — OnboardingStep2Whitelist에서 raw "허용 목록" 대신 사용하는 친화 언어 모음.
    public enum Whitelist {
        /// 화면 상단 헤더 타이틀
        public static let title    = "사용 가능한 사람 목록"
        /// User IDs 입력 카드 제목
        public static let userIdsTitle = "사용 가능한 사람 (텔레그램 사용자 번호)"
        /// 목록이 비어있을 때 경고 첫 줄
        public static let emptyWarningTitle = "모든 사용자 허용 (위험)"
        /// 목록이 비어있을 때 경고 본문
        public static let emptyHint = "비워두면 누구나 이 봇을 사용할 수 있어요. 보안을 위해 직접 추가를 권장해요."
        /// 헤더 서브타이틀
        public static let subtitle  = "이 봇에 접근을 허용할 텔레그램 사용자 ID를 지정하세요. 나중에 봇 설정에서 언제든 수정할 수 있어요."
    }

    // MARK: - 섹션 헤더 / 안내

    public static let hubFooterBots     = "봇"
    public static let hubFooterGroups   = "그룹"
    public static let hubFooterBindings = "연결"
    public static let hubFooterErrors   = "에러"
}
