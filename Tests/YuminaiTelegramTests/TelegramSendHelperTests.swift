import Foundation
import Testing
import YuminaiCore
@testable import YuminaiTelegram

/// **ADR-099 P1** — TelegramSendHelper 통합 테스트.
///
/// P1-1: artifact store wire-up (store 호출 + UUID 반환)
/// P1-2: formatter wire-up (formatDiff/formatLog 사용 확인)
/// P1-3: LargePayloadSender 통합 (크기별 라우팅)
/// P1-4: HITL edit 포맷 + editMessageText 호출
@Suite("TelegramSendHelper (ADR-099 P1)")
struct TelegramSendHelperTests {

    // MARK: - P1-1 + P1-2: sendDiffPreview — store + formatter wire-up

    @Test("sendDiffPreview — artifact store에 저장되고 UUID 반환")
    func sendDiffPreviewStoresArtifact() async throws {
        let bot = MockTelegramBot()
        let store = TelegramArtifactStore()

        let id = try await TelegramSendHelper.sendDiffPreview(
            diff: "diff --git a/Foo.swift b/Foo.swift\n+added line",
            files: 1,
            added: 1,
            removed: 0,
            workspace: "TestWorkspace",
            to: 1001,
            store: store,
            client: bot
        )

        // P1-1: store에 저장됨
        let fetched = await store.fetch(id)
        #expect(fetched != nil)
        if case .diff(_, let files, let added, let removed, let ws) = fetched {
            #expect(files == 1)
            #expect(added == 1)
            #expect(removed == 0)
            #expect(ws == "TestWorkspace")
        } else {
            Issue.record("Expected .diff artifact")
        }
    }

    @Test("sendDiffPreview — formatter 적용 (deep link UUID 포함)")
    func sendDiffPreviewUsesFormatter() async throws {
        let bot = MockTelegramBot()
        let store = TelegramArtifactStore()

        let id = try await TelegramSendHelper.sendDiffPreview(
            diff: "diff --git a/Bar.swift b/Bar.swift\n+new line",
            files: 1,
            added: 1,
            removed: 0,
            workspace: nil,
            to: 2001,
            store: store,
            client: bot
        )

        // P1-2: formatter가 적용된 메시지 발송 확인
        let sentLog = await bot.sentLog
        #expect(!sentLog.isEmpty)
        let sentText = sentLog.first?.text ?? ""

        // formatter 출력: "📝 Diff Preview", code fence, deep link UUID
        #expect(sentText.contains("📝 Diff Preview"))
        #expect(sentText.contains("```diff"))
        let uuidStr = id.uuidString.lowercased()
        #expect(sentText.contains(uuidStr))
        // deep link 형식: yuminai://diff/<uuid>
        #expect(sentText.contains("yuminai://diff/"))
    }

    @Test("sendDiffPreview — 짧은 diff는 send 경로 (sendDocument 아님)")
    func sendDiffPreviewShortUsesDirectSend() async throws {
        let bot = MockTelegramBot()
        let store = TelegramArtifactStore()

        try await TelegramSendHelper.sendDiffPreview(
            diff: "small diff",
            files: 1,
            added: 1,
            removed: 0,
            workspace: nil,
            to: 3001,
            store: store,
            client: bot
        )

        // P1-3: 짧은 내용 → sendDocument 미호출
        let docLog = await bot.sentDocumentLog
        let sentLog = await bot.sentLog
        #expect(docLog.isEmpty)
        #expect(!sentLog.isEmpty)
    }

    // MARK: - P1-1 + P1-2: sendBuildLog — store + formatter wire-up

    @Test("sendBuildLog — artifact store에 저장되고 UUID 반환")
    func sendBuildLogStoresArtifact() async throws {
        let bot = MockTelegramBot()
        let store = TelegramArtifactStore()

        let id = try await TelegramSendHelper.sendBuildLog(
            log: "Build complete!\nAll tests passed.",
            title: "swift test",
            elapsed: 12.5,
            success: true,
            to: 4001,
            store: store,
            client: bot
        )

        let fetched = await store.fetch(id)
        #expect(fetched != nil)
        if case .log(_, let title, let elapsed, let success) = fetched {
            #expect(title == "swift test")
            #expect(elapsed == 12.5)
            #expect(success == true)
        } else {
            Issue.record("Expected .log artifact")
        }
    }

    @Test("sendBuildLog — formatter 적용 (성공/실패 배지 + deep link)")
    func sendBuildLogUsesFormatter() async throws {
        let bot = MockTelegramBot()
        let store = TelegramArtifactStore()

        let id = try await TelegramSendHelper.sendBuildLog(
            log: "Build failed: error on line 42",
            title: "Build · Yuminai",
            elapsed: 3.0,
            success: false,
            to: 5001,
            store: store,
            client: bot
        )

        let sentLog = await bot.sentLog
        #expect(!sentLog.isEmpty)
        let sentText = sentLog.first?.text ?? ""

        // formatter 출력: badge, title, deep link
        #expect(sentText.contains("❌ FAILED"))
        #expect(sentText.contains("Build · Yuminai"))
        let uuidStr = id.uuidString.lowercased()
        #expect(sentText.contains(uuidStr))
        #expect(sentText.contains("yuminai://log/"))
    }

    // MARK: - P1-4: HITL edit format

    @Test("formatHITLResponseEdit — approved 포맷")
    func hitlEditApprovedFormat() {
        let text = TelegramSendHelper.formatHITLResponseEdit(
            response: .approved(by: "telegram:user:42"),
            originalAction: "git push --force"
        )
        #expect(text.contains("✅ Approved by @42"))
        #expect(text.contains("git push --force"))
    }

    @Test("formatHITLResponseEdit — rejected 포맷")
    func hitlEditRejectedFormat() {
        let text = TelegramSendHelper.formatHITLResponseEdit(
            response: .rejected(by: "desktop"),
            originalAction: "rm -rf /tmp"
        )
        #expect(text.contains("❌ Rejected by desktop"))
        #expect(text.contains("rm -rf /tmp"))
    }

    @Test("formatHITLResponseEdit — timeout 포맷")
    func hitlEditTimeoutFormat() {
        let text = TelegramSendHelper.formatHITLResponseEdit(
            response: .timeout,
            originalAction: "dangerous action"
        )
        #expect(text.contains("⏱ Timeout — action cancelled"))
        #expect(text.contains("dangerous action"))
    }

    @Test("formatHITLResponseEdit — cancelled 포맷")
    func hitlEditCancelledFormat() {
        let text = TelegramSendHelper.formatHITLResponseEdit(
            response: .cancelled,
            originalAction: "some action"
        )
        #expect(text.contains("🚫 Cancelled — action aborted"))
        #expect(text.contains("some action"))
    }

    @Test("editHITLMessage — client.edit 호출 확인")
    func editHITLMessageCallsClientEdit() async {
        let bot = MockTelegramBot()

        await TelegramSendHelper.editHITLMessage(
            response: .approved(by: "desktop"),
            originalAction: "git push --force",
            messageId: 999,
            chatId: 1001,
            client: bot
        )

        let editLog = await bot.editLog
        #expect(editLog.count == 1)
        #expect(editLog[0].messageId == 999)
        #expect(editLog[0].chatId == 1001)
        #expect(editLog[0].text.contains("✅ Approved by desktop"))
    }

    // MARK: - P1-4: HITLCoordinator.Request struct fields

    @Test("HITLCoordinator.Request — telegramMessageId/chatId 필드 저장")
    func requestHasTelegramFields() async {
        let coordinator = TelegramHITLCoordinator()

        let requestTask = Task {
            await coordinator.request(action: "test action", workspace: nil, diffPreview: nil, timeout: 30)
        }

        try? await Task.sleep(for: .milliseconds(50))

        let pending = await coordinator.pendingRequests()
        #expect(pending.count == 1)
        let req = pending[0]

        // 초기에는 nil
        #expect(req.telegramMessageId == nil)
        #expect(req.telegramChatId == nil)

        // setTelegramMessageId 호출
        await coordinator.setTelegramMessageId(12345, chatId: 9999, for: req.id)

        let updated = await coordinator.pendingRequests()
        #expect(updated.count == 1)
        #expect(updated[0].telegramMessageId == 12345)
        #expect(updated[0].telegramChatId == 9999)

        await coordinator.cancel(id: req.id)
        _ = await requestTask.value
    }

    @Test("HITLCoordinator.Request — Equatable (새 필드 포함)")
    func requestEquatableWithNewFields() async {
        let coordinator = TelegramHITLCoordinator()

        let requestTask = Task {
            await coordinator.request(action: "eq test", workspace: nil, diffPreview: nil, timeout: 5)
        }

        try? await Task.sleep(for: .milliseconds(50))
        let pending = await coordinator.pendingRequests()
        let req = pending[0]

        // 같은 id면 동일
        let copy = TelegramHITLCoordinator.Request(
            id: req.id,
            action: req.action,
            workspace: req.workspace,
            diffPreview: req.diffPreview,
            createdAt: req.createdAt,
            timeoutSeconds: req.timeoutSeconds,
            telegramMessageId: nil,
            telegramChatId: nil
        )
        #expect(req == copy)

        await coordinator.cancel(id: req.id)
        _ = await requestTask.value
    }

    // MARK: - P1-3: LargePayloadSender — sendDocument routing via helper

    @Test("sendBuildLog — 5MB+ 로그는 sendDocument 호출")
    func sendBuildLogLargeUsesDocument() async throws {
        let bot = MockTelegramBot()
        let store = TelegramArtifactStore()
        // 6MB 로그
        let largeLog = String(repeating: "log line content\n", count: 6 * 1024 * 60)

        try await TelegramSendHelper.sendBuildLog(
            log: largeLog,
            title: "Big Build",
            elapsed: 60.0,
            success: true,
            to: 7001,
            store: store,
            client: bot
        )

        let docLog = await bot.sentDocumentLog
        #expect(!docLog.isEmpty)
        #expect(docLog[0].chatId == 7001)
    }

    // MARK: - ADR-115 P1-1: workspaceName prefix

    @Test("sendBuildLog — workspaceName 있으면 📁 prefix 포함")
    func sendBuildLogWithWorkspaceName() async throws {
        let bot = MockTelegramBot()
        let store = TelegramArtifactStore()

        try await TelegramSendHelper.sendBuildLog(
            log: "Build OK",
            title: "swift test",
            elapsed: 1.5,
            success: true,
            to: 8001,
            workspaceName: "MyProject",
            store: store,
            client: bot
        )

        let sentLog = await bot.sentLog
        #expect(!sentLog.isEmpty)
        let text = sentLog.first?.text ?? ""
        #expect(text.hasPrefix("📁 [MyProject] ▶ swift test"))
    }

    @Test("sendBuildLog — workspaceName nil이면 prefix 없음")
    func sendBuildLogWithoutWorkspaceName() async throws {
        let bot = MockTelegramBot()
        let store = TelegramArtifactStore()

        try await TelegramSendHelper.sendBuildLog(
            log: "Build OK",
            title: "swift build",
            elapsed: 2.0,
            success: true,
            to: 8002,
            workspaceName: nil,
            store: store,
            client: bot
        )

        let sentLog = await bot.sentLog
        #expect(!sentLog.isEmpty)
        let text = sentLog.first?.text ?? ""
        #expect(!text.hasPrefix("📁"))
    }

    @Test("sendDiffPreview — workspaceName 있으면 📁 prefix 포함")
    func sendDiffPreviewWithWorkspaceName() async throws {
        let bot = MockTelegramBot()
        let store = TelegramArtifactStore()

        try await TelegramSendHelper.sendDiffPreview(
            diff: "diff --git a/A.swift b/A.swift\n+new line",
            files: 1,
            added: 1,
            removed: 0,
            workspace: nil,
            workspaceName: "WorkspaceAlpha",
            to: 9001,
            store: store,
            client: bot
        )

        let sentLog = await bot.sentLog
        #expect(!sentLog.isEmpty)
        let text = sentLog.first?.text ?? ""
        #expect(text.hasPrefix("📁 [WorkspaceAlpha] ▶ git diff"))
    }

    @Test("sendDiffPreview — workspaceName nil이면 workspace fallback 또는 prefix 없음")
    func sendDiffPreviewNoWorkspaceName() async throws {
        let bot = MockTelegramBot()
        let store = TelegramArtifactStore()

        try await TelegramSendHelper.sendDiffPreview(
            diff: "diff --git a/B.swift b/B.swift\n+line",
            files: 1,
            added: 1,
            removed: 0,
            workspace: nil,
            workspaceName: nil,
            to: 9002,
            store: store,
            client: bot
        )

        let sentLog = await bot.sentLog
        #expect(!sentLog.isEmpty)
        let text = sentLog.first?.text ?? ""
        // workspace와 workspaceName 둘 다 nil → prefix 없음
        #expect(!text.hasPrefix("📁"))
    }
}
