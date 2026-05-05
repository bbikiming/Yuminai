import Foundation
import YuminaiCore

/// **ADR-099 P1** — Telegram diff/log 발송 헬퍼.
///
/// P1-1: `TelegramArtifactStore.store()` wire-up
/// P1-2: `TelegramMessageFormatter.formatDiff/formatLog` production 사용
/// P1-3: `TelegramLargePayloadSender.sendOrAttach` 통합 (5MB+ 자동 sendDocument)
///
/// 모든 발송 경로가 이 헬퍼를 통해 formatter → artifact store → large payload 라우팅을
/// 일관되게 거친다.
public enum TelegramSendHelper {

    // MARK: - Diff Preview

    /// diff를 포맷하고 artifact store에 저장한 뒤 텔레그램으로 발송한다.
    ///
    /// - Parameters:
    ///   - diff: raw git diff 문자열
    ///   - files: 변경된 파일 수
    ///   - added: 추가된 라인 수
    ///   - removed: 삭제된 라인 수
    ///   - workspace: 워크스페이스 이름 (nil 가능). artifact store에 연결됨.
    ///   - workspaceName: 발송 메시지 prefix용 이름 (ADR-115 P1-1).
    ///     nil이면 `workspace`와 동일하게 처리. 둘 다 nil이면 prefix 생략.
    ///   - chatId: 대상 chat ID
    ///   - store: `TelegramArtifactStore` — 저장 후 deep link UUID 생성
    ///   - client: `TelegramClient` 구현체
    /// - Returns: 저장된 artifact UUID (caller가 필요 시 보관)
    @discardableResult
    public static func sendDiffPreview(
        diff: String,
        files: Int,
        added: Int,
        removed: Int,
        workspace: String?,
        workspaceName: String? = nil,
        to chatId: Int64,
        store: TelegramArtifactStore,
        client: any TelegramClient
    ) async throws -> UUID {
        // P1-1: store artifact → UUID
        let id = await store.store(
            .diff(content: diff, files: files, added: added, removed: removed, workspace: workspace)
        )

        let caption = "📝 Diff Preview · \(files) file\(files == 1 ? "" : "s"), +\(added)/-\(removed)"
        let diffByteCount = diff.utf8.count

        // ADR-115 P1-1 — 워크스페이스 prefix 라인.
        let effectiveName = workspaceName ?? workspace
        let workspacePrefix: String? = effectiveName.flatMap { name in
            name.trimmingCharacters(in: .whitespaces).isEmpty ? nil : "📁 [\(name)] ▶ git diff"
        }

        // P1-3: 5MB+ raw diff → sendDocument (전체 내용 첨부 + caption preview)
        // < 5MB → P1-2 formatter 적용 후 send
        if TelegramMessageFormatter.shouldSendAsDocument(byteCount: diffByteCount) {
            guard let data = diff.data(using: .utf8) else { return id }
            let fullCaption = workspacePrefix.map { "\($0)\n\(caption)" } ?? caption
            _ = try await client.sendDocument(
                fileName: "diff-\(id.uuidString.prefix(8)).txt",
                data: data,
                caption: String(fullCaption.prefix(1024)),
                to: chatId
            )
        } else {
            // P1-2: formatter 사용 (deep link UUID 포함)
            let formatted = TelegramMessageFormatter.formatDiff(
                diff,
                files: files,
                added: added,
                removed: removed,
                deepLinkId: id
            )
            let finalText = workspacePrefix.map { "\($0)\n\(formatted)" } ?? formatted
            try await TelegramLargePayloadSender.sendOrAttach(
                text: finalText,
                fileName: "diff-\(id.uuidString.prefix(8)).txt",
                caption: caption,
                to: chatId,
                client: client
            )
        }

        return id
    }

    // MARK: - Build/Test Log

    /// build/test 로그를 포맷하고 artifact store에 저장한 뒤 텔레그램으로 발송한다.
    ///
    /// - Parameters:
    ///   - log: 전체 로그 문자열
    ///   - title: 로그 제목 (예: "swift test")
    ///   - elapsed: 소요 시간 (초)
    ///   - success: 성공 여부
    ///   - chatId: 대상 chat ID
    ///   - workspaceName: 워크스페이스 이름 — 멀티 chat 환경에서 출처 표시용 (ADR-115 P1-1).
    ///     nil이면 prefix 없이 기존 포맷 유지.
    ///   - store: `TelegramArtifactStore`
    ///   - client: `TelegramClient` 구현체
    /// - Returns: 저장된 artifact UUID
    @discardableResult
    public static func sendBuildLog(
        log: String,
        title: String,
        elapsed: TimeInterval,
        success: Bool,
        to chatId: Int64,
        workspaceName: String? = nil,
        store: TelegramArtifactStore,
        client: any TelegramClient
    ) async throws -> UUID {
        // P1-1: store artifact → UUID
        let id = await store.store(
            .log(content: log, title: title, elapsed: elapsed, success: success)
        )

        let badge = success ? "PASSED" : "FAILED"
        let caption = "🔨 \(title) · \(badge)"
        let logByteCount = log.utf8.count

        // ADR-115 P1-1 — 워크스페이스 prefix 라인.
        // 멀티 chat 환경에서 어느 워크스페이스 결과인지 한눈에 식별 가능.
        let workspacePrefix: String? = workspaceName.flatMap { name in
            name.trimmingCharacters(in: .whitespaces).isEmpty ? nil : "📁 [\(name)] ▶ \(title)"
        }

        // P1-3: 5MB+ raw log → sendDocument (전체 내용 첨부 + caption preview)
        // < 5MB → P1-2 formatter 적용 후 send
        if TelegramMessageFormatter.shouldSendAsDocument(byteCount: logByteCount) {
            guard let data = log.data(using: .utf8) else { return id }
            let fullCaption = workspacePrefix.map { "\($0)\n\(caption)" } ?? caption
            _ = try await client.sendDocument(
                fileName: "log-\(id.uuidString.prefix(8)).txt",
                data: data,
                caption: String(fullCaption.prefix(1024)),
                to: chatId
            )
        } else {
            // P1-2: formatter 사용 (deep link UUID 포함)
            let formatted = TelegramMessageFormatter.formatLog(
                log,
                title: title,
                elapsed: elapsed,
                success: success,
                deepLinkId: id
            )
            let finalText = workspacePrefix.map { "\($0)\n\(formatted)" } ?? formatted
            try await TelegramLargePayloadSender.sendOrAttach(
                text: finalText,
                fileName: "log-\(id.uuidString.prefix(8)).txt",
                caption: caption,
                to: chatId,
                client: client
            )
        }

        return id
    }

    // MARK: - HITL Edit Text

    /// HITL 응답 후 텔레그램 메시지를 자동으로 edit한다.
    ///
    /// - Parameters:
    ///   - response: HITL 응답 결과
    ///   - originalAction: 원래 요청된 action 설명
    ///   - messageId: edit할 텔레그램 메시지 ID
    ///   - chatId: 대상 chat ID
    ///   - client: `TelegramClient` 구현체
    public static func editHITLMessage(
        response: TelegramHITLCoordinator.HITLResponse,
        originalAction: String,
        messageId: Int64,
        chatId: Int64,
        client: any TelegramClient
    ) async {
        let editText = formatHITLResponseEdit(
            response: response,
            originalAction: originalAction
        )
        try? await client.edit(messageId: messageId, in: chatId, text: editText)
    }

    // MARK: - Private Helpers

    /// HITL 응답 포맷 문자열 생성.
    static func formatHITLResponseEdit(
        response: TelegramHITLCoordinator.HITLResponse,
        originalAction: String
    ) -> String {
        let actionPreview = String(originalAction.prefix(100))
        let timestamp = ISO8601DateFormatter.string(
            from: Date(),
            timeZone: TimeZone.current,
            formatOptions: [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        )

        switch response {
        case .approved(let by):
            let displayBy = by.hasPrefix("telegram:user:") ? "@\(by.dropFirst("telegram:user:".count))" : by
            return "✅ Approved by \(displayBy) · \(timestamp)\n\nAction: `\(actionPreview)`"
        case .rejected(let by):
            let displayBy = by.hasPrefix("telegram:user:") ? "@\(by.dropFirst("telegram:user:".count))" : by
            return "❌ Rejected by \(displayBy) · \(timestamp)\n\nAction: `\(actionPreview)`"
        case .timeout:
            return "⏱ Timeout — action cancelled · \(timestamp)\n\nAction: `\(actionPreview)`"
        case .cancelled:
            return "🚫 Cancelled — action aborted · \(timestamp)\n\nAction: `\(actionPreview)`"
        }
    }
}
