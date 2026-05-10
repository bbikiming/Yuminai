import Foundation
import Testing
@testable import YuminaiCore

/// **ADR-151** — TelegramHandoff 데이터 모델 + 메시지 포맷터 단위 테스트.

@Suite("TelegramHandoffRequest — 모델 (ADR-151)")
struct TelegramHandoffRequestTests {

    @Test("기본 init — 모든 필드 정확히 저장됨")
    func initStoresAllFields() {
        let sessionId = UUID()
        let workspaceId = UUID()
        let botId = UUID()
        let chatId: Int64 = 123456789
        let now = Date()
        let req = TelegramHandoffRequest(
            sessionId: sessionId,
            workspaceId: workspaceId,
            botId: botId,
            chatId: chatId,
            initiatedAt: now,
            summary: "테스트 요약",
            lastUserPrompt: "마지막 사용자 입력"
        )
        #expect(req.sessionId == sessionId)
        #expect(req.workspaceId == workspaceId)
        #expect(req.botId == botId)
        #expect(req.chatId == chatId)
        #expect(req.summary == "테스트 요약")
        #expect(req.lastUserPrompt == "마지막 사용자 입력")
    }

    @Test("nil sessionId/workspaceId 허용 (자유 대화)")
    func nilSessionAndWorkspaceAllowed() {
        let req = TelegramHandoffRequest(
            sessionId: nil,
            workspaceId: nil,
            botId: UUID(),
            chatId: 99,
            summary: "자유 대화 핸드오프",
            lastUserPrompt: nil
        )
        #expect(req.sessionId == nil)
        #expect(req.workspaceId == nil)
        #expect(req.lastUserPrompt == nil)
    }

    @Test("Codable 왕복 — 인코딩 후 디코딩 일치")
    func codableRoundtrip() throws {
        let original = TelegramHandoffRequest(
            sessionId: UUID(),
            workspaceId: UUID(),
            botId: UUID(),
            chatId: 55555,
            summary: "코더블 테스트",
            lastUserPrompt: "프롬프트"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TelegramHandoffRequest.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.sessionId == original.sessionId)
        #expect(decoded.chatId == original.chatId)
        #expect(decoded.summary == original.summary)
        #expect(decoded.lastUserPrompt == original.lastUserPrompt)
    }

    @Test("Hashable + Equatable — 동일한 모든 필드면 같음")
    func hashableEquality() {
        let id = UUID()
        let botId = UUID()
        let sessionId = UUID()
        let workspaceId = UUID()
        let now = Date(timeIntervalSince1970: 1000)
        let a = TelegramHandoffRequest(
            id: id, sessionId: sessionId, workspaceId: workspaceId,
            botId: botId, chatId: 1, initiatedAt: now, summary: "a", lastUserPrompt: nil
        )
        let b = TelegramHandoffRequest(
            id: id, sessionId: sessionId, workspaceId: workspaceId,
            botId: botId, chatId: 1, initiatedAt: now, summary: "a", lastUserPrompt: nil
        )
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test("다른 id는 다름 (Set에 2개 존재)")
    func differentIdNotEqual() {
        let a = TelegramHandoffRequest(
            sessionId: nil, workspaceId: nil,
            botId: UUID(), chatId: 1, summary: "a", lastUserPrompt: nil
        )
        let b = TelegramHandoffRequest(
            sessionId: nil, workspaceId: nil,
            botId: UUID(), chatId: 1, summary: "a", lastUserPrompt: nil
        )
        // 다른 UUID라서 다른 id → Set에 2개 들어감
        let set: Set<TelegramHandoffRequest> = [a, b]
        #expect(set.count == 2)
    }
}

// MARK: - TelegramHandoffStatus

@Suite("TelegramHandoffStatus (ADR-151)")
struct TelegramHandoffStatusTests {

    @Test("모든 case rawValue 정확")
    func allCasesHaveCorrectRawValue() {
        #expect(TelegramHandoffStatus.sent.rawValue == "sent")
        #expect(TelegramHandoffStatus.pending.rawValue == "pending")
        #expect(TelegramHandoffStatus.received.rawValue == "received")
        #expect(TelegramHandoffStatus.completed.rawValue == "completed")
        #expect(TelegramHandoffStatus.failed.rawValue == "failed")
    }

    @Test("Codable 왕복")
    func codableRoundtrip() throws {
        for status in [TelegramHandoffStatus.sent, .pending, .received, .completed, .failed] {
            let data = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(TelegramHandoffStatus.self, from: data)
            #expect(decoded == status)
        }
    }
}

// MARK: - TelegramHandoffError

@Suite("TelegramHandoffError (ADR-151)")
struct TelegramHandoffErrorTests {

    @Test("botNotActive — errorDescription 한국어")
    func botNotActiveDescription() {
        let err = TelegramHandoffError.botNotActive
        #expect(err.errorDescription?.contains("텔레그램 봇") == true)
        #expect(err.errorDescription?.contains("활성화") == true)
    }

    @Test("noBinding — errorDescription 한국어")
    func noBindingDescription() {
        let err = TelegramHandoffError.noBinding
        #expect(err.errorDescription?.contains("채팅") == true)
    }

    @Test("noMatchingBinding — errorDescription 한국어")
    func noMatchingBindingDescription() {
        let err = TelegramHandoffError.noMatchingBinding
        #expect(err.errorDescription?.contains("워크스페이스") == true)
    }

    @Test("sendFailed — underlying error 포함")
    func sendFailedDescription() {
        let underlying = NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "네트워크 오류"])
        let err = TelegramHandoffError.sendFailed(underlying: underlying)
        #expect(err.errorDescription?.contains("전송 실패") == true)
        #expect(err.errorDescription?.contains("네트워크 오류") == true)
    }
}

// MARK: - TelegramHandoffFormatter

@Suite("TelegramHandoffFormatter (ADR-151)")
struct TelegramHandoffFormatterTests {

    @Test("워크스페이스 이름 포함 메시지 생성")
    func includesWorkspaceName() {
        let msg = TelegramHandoffFormatter.format(
            workspaceName: "my-project",
            lastUserPrompt: nil,
            sessionTitle: nil
        )
        #expect(msg.contains("📱 작업 이어가기"))
        #expect(msg.contains("my-project"))
        #expect(msg.contains("답장 보내면"))
    }

    @Test("워크스페이스 없으면 suffix 없음")
    func noWorkspaceNoSuffix() {
        let msg = TelegramHandoffFormatter.format(
            workspaceName: nil,
            lastUserPrompt: nil,
            sessionTitle: nil
        )
        #expect(msg.contains("📱 작업 이어가기\n"))
    }

    @Test("lastUserPrompt 포함 — 짧으면 전체")
    func shortPromptIncluded() {
        let msg = TelegramHandoffFormatter.format(
            workspaceName: nil,
            lastUserPrompt: "이거 고쳐줘",
            sessionTitle: nil
        )
        #expect(msg.contains("최근 작업: 이거 고쳐줘"))
    }

    @Test("lastUserPrompt 120자 초과 시 truncate")
    func longPromptTruncated() {
        let longPrompt = String(repeating: "가", count: 150)
        let msg = TelegramHandoffFormatter.format(
            workspaceName: nil,
            lastUserPrompt: longPrompt,
            sessionTitle: nil
        )
        #expect(msg.contains("최근 작업:"))
        #expect(msg.contains("…"))
        // 최대 120자 + "…" = 121자
        let afterPrefix = msg.components(separatedBy: "최근 작업: ").last ?? ""
        let oneLine = afterPrefix.components(separatedBy: "\n").first ?? ""
        #expect(oneLine.count <= 122)  // 120 가 + "…" + 여유
    }

    @Test("prompt 없고 sessionTitle 있으면 title 사용")
    func sessionTitleFallback() {
        let msg = TelegramHandoffFormatter.format(
            workspaceName: nil,
            lastUserPrompt: nil,
            sessionTitle: "버그 디버깅 세션"
        )
        #expect(msg.contains("세션: 버그 디버깅 세션"))
    }

    @Test("prompt 있으면 title 무시 (prompt 우선)")
    func promptTakesPriorityOverTitle() {
        let msg = TelegramHandoffFormatter.format(
            workspaceName: nil,
            lastUserPrompt: "실제 작업",
            sessionTitle: "세션 제목"
        )
        #expect(msg.contains("최근 작업: 실제 작업"))
        #expect(!msg.contains("세션 제목"))
    }

    @Test("멀티라인 prompt → 단일 라인으로 변환")
    func multilinePromptFlattened() {
        let multiline = "첫째 줄\n둘째 줄\n셋째 줄"
        let msg = TelegramHandoffFormatter.format(
            workspaceName: nil,
            lastUserPrompt: multiline,
            sessionTitle: nil
        )
        // 최근 작업 행이 줄바꿈 없이 이어짐
        let lines = msg.components(separatedBy: "\n")
        let promptLine = lines.first { $0.hasPrefix("최근 작업:") }
        #expect(promptLine != nil)
        #expect(promptLine?.contains("첫째 줄") == true)
    }

    @Test("기본 메시지 구조 — 4줄 이상")
    func messageHasMultipleLines() {
        let msg = TelegramHandoffFormatter.format(
            workspaceName: "ws",
            lastUserPrompt: "작업 내용",
            sessionTitle: nil
        )
        let lines = msg.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(lines.count >= 4)
    }
}
