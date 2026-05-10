import Foundation

/// **ADR-151** — 텔레그램 핸드오프: 데스크탑 작업 세션을 텔레그램으로 이어서 작업할 수 있도록 한다.
///
/// ## 사용 시나리오
/// 1. 사용자가 데스크탑 Yuminai에서 채팅 중
/// 2. 외출/이동 시 "📱 텔레그램으로 이어서" 버튼 클릭
/// 3. binding된 텔레그램 chat에 컨텍스트 요약 전송
/// 4. 사용자가 텔레그램에서 메시지 보내면 → 같은 session으로 routing

// MARK: - TelegramHandoffRequest

/// 텔레그램 핸드오프 요청 데이터 (단방향 — 데스크탑 → 텔레그램).
public struct TelegramHandoffRequest: Sendable, Codable, Hashable, Identifiable {
    public let id: UUID
    /// 현재 작업 중이던 ChatSession ID (nil이면 워크스페이스 기본 대화).
    public let sessionId: UUID?
    /// 어느 워크스페이스에서 작업 중이었는지.
    public let workspaceId: UUID?
    /// 어느 봇으로 보낼지 (BotChatBinding.botId).
    public let botId: UUID
    /// 어느 chat으로 보낼지 (BotChatBinding.chatId).
    public let chatId: Int64
    /// 핸드오프 시작 시각.
    public let initiatedAt: Date
    /// 사용자에게 보낼 컨텍스트 요약 메시지.
    public let summary: String
    /// 마지막 사용자 입력 (재참고용, nil이면 없음).
    public let lastUserPrompt: String?

    public init(
        id: UUID = UUID(),
        sessionId: UUID?,
        workspaceId: UUID?,
        botId: UUID,
        chatId: Int64,
        initiatedAt: Date = Date(),
        summary: String,
        lastUserPrompt: String?
    ) {
        self.id = id
        self.sessionId = sessionId
        self.workspaceId = workspaceId
        self.botId = botId
        self.chatId = chatId
        self.initiatedAt = initiatedAt
        self.summary = summary
        self.lastUserPrompt = lastUserPrompt
    }
}

// MARK: - TelegramHandoffStatus

/// 핸드오프 진행 상태.
public enum TelegramHandoffStatus: String, Sendable, Codable {
    /// 텔레그램 메시지 전송 완료.
    case sent
    /// 사용자 텔레그램 응답 대기 중.
    case pending
    /// 사용자가 텔레그램에서 메시지 보냄 (활성 상태).
    case received
    /// 세션 종료 (사용자가 데스크탑으로 복귀).
    case completed
    /// 전송 실패 (봇 비활성화, 네트워크 오류 등).
    case failed
}

// MARK: - TelegramHandoffError

/// 핸드오프 실패 원인.
public enum TelegramHandoffError: Error, LocalizedError {
    /// 텔레그램 봇이 활성화되어 있지 않음.
    case botNotActive
    /// 활성 binding이 없음 (어느 chat으로 보낼지 알 수 없음).
    case noBinding
    /// binding은 있지만 활성 워크스페이스와 매칭되는 것이 없음.
    case noMatchingBinding
    /// 메시지 전송 실패.
    case sendFailed(underlying: any Error)

    public var errorDescription: String? {
        switch self {
        case .botNotActive:
            return "텔레그램 봇이 활성화되어 있지 않아요. 설정 → Telegram에서 봇을 켜주세요."
        case .noBinding:
            return "연결된 텔레그램 채팅이 없어요. 먼저 텔레그램 허브에서 봇과 채팅을 연결해 주세요."
        case .noMatchingBinding:
            return "현재 워크스페이스에 연결된 텔레그램 채팅을 찾을 수 없어요."
        case .sendFailed(let err):
            return "텔레그램 전송 실패: \(err.localizedDescription)"
        }
    }
}

// MARK: - Handoff Message Formatter

/// 텔레그램 핸드오프 메시지 포맷터.
public enum TelegramHandoffFormatter {
    /// 사용자 친화 한국어 핸드오프 메시지 생성.
    ///
    /// 형식:
    /// ```
    /// 📱 작업 이어가기 — [워크스페이스명]
    /// Yuminai 데스크탑에서 작업 중이던 세션을 여기서 계속할 수 있어요.
    /// 최근 작업: <마지막 user prompt 짧은 요약>
    /// 답장 보내면 같은 세션에서 이어집니다.
    /// ```
    public static func format(
        workspaceName: String?,
        lastUserPrompt: String?,
        sessionTitle: String?
    ) -> String {
        var lines: [String] = []

        let wsSuffix = workspaceName.map { " — \($0)" } ?? ""
        lines.append("📱 작업 이어가기\(wsSuffix)")
        lines.append("Yuminai 데스크탑에서 작업 중이던 세션을 여기서 계속할 수 있어요.")

        if let prompt = lastUserPrompt, !prompt.isEmpty {
            let truncated = prompt.count > 120
                ? String(prompt.prefix(120)) + "…"
                : prompt
            let oneLine = truncated.replacingOccurrences(of: "\n", with: " ")
            lines.append("최근 작업: \(oneLine)")
        } else if let title = sessionTitle, !title.isEmpty {
            lines.append("세션: \(title)")
        }

        lines.append("답장 보내면 같은 세션에서 이어집니다.")
        return lines.joined(separator: "\n")
    }
}
