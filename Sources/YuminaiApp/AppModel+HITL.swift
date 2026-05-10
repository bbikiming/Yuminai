import Foundation
import os
import YuminaiCore
import YuminaiTelegram

// ADR-127 — AppModel.swift 분할: HITL 도메인 (Human-in-the-Loop Coordinator + diff/build 전송)
extension AppModel {

    // MARK: - ADR-099 P1-1/P1-2/P1-3 — Artifact + Formatter + LargePayload wire-up

    /// diff를 formatter로 포맷 → artifact store 저장 → LargePayloadSender로 발송.
    ///
    /// `TelegramSendHelper.sendDiffPreview`의 AppModel 진입점.
    /// - Returns: 저장된 artifact UUID (nil이면 Telegram 미설정)
    @discardableResult
    public func sendDiffPreviewToTelegram(
        diff: String,
        files: Int,
        added: Int,
        removed: Int,
        workspace: String?,
        chatId: Int64? = nil
    ) async -> UUID? {
        guard let bot = telegramBot else { return nil }
        let targetChatId = chatId ?? preferences.telegramChatId
        guard let targetChatId else { return nil }
        do {
            return try await TelegramSendHelper.sendDiffPreview(
                diff: diff,
                files: files,
                added: added,
                removed: removed,
                workspace: workspace,
                to: targetChatId,
                store: telegramArtifactStore,
                client: bot
            )
        } catch {
            logger.error("sendDiffPreviewToTelegram 실패: \(error.localizedDescription)")
            return nil
        }
    }

    /// build/test log를 formatter로 포맷 → artifact store 저장 → LargePayloadSender로 발송.
    ///
    /// `TelegramSendHelper.sendBuildLog`의 AppModel 진입점.
    /// - Returns: 저장된 artifact UUID (nil이면 Telegram 미설정)
    @discardableResult
    public func sendBuildLogToTelegram(
        log: String,
        title: String,
        elapsed: TimeInterval,
        success: Bool,
        chatId: Int64? = nil
    ) async -> UUID? {
        guard let bot = telegramBot else { return nil }
        let targetChatId = chatId ?? preferences.telegramChatId
        guard let targetChatId else { return nil }
        // ADR-115 P1-1 — 현재 워크스페이스 이름을 prefix로 전달
        let wsName: String? = currentWorkspace?.name
        do {
            return try await TelegramSendHelper.sendBuildLog(
                log: log,
                title: title,
                elapsed: elapsed,
                success: success,
                to: targetChatId,
                workspaceName: wsName,
                store: telegramArtifactStore,
                client: bot
            )
        } catch {
            logger.error("sendBuildLogToTelegram 실패: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - ADR-094 Phase 3 — HITL Coordinator

    /// **ADR-094 Phase 3** — HITL coordinator 초기화 + AsyncStream 구독.
    /// `setupTelegram()` 완료 후 호출.
    func setupTelegramHITLCoordinator() {
        let coordinator = TelegramHITLCoordinator()
        hitlCoordinator = coordinator

        // **ADR-098 P0-1** — HITL coordinator를 sessionBridge에 주입해 destructive action 차단 흐름 활성화.
        let timeoutSecs = preferences.hitlTimeoutSeconds
        Task { [weak self] in
            await self?.sessionBridge?.setHITLCoordinator(coordinator, timeoutSeconds: timeoutSecs)
        }

        Task { [weak self] in
            let stream = await coordinator.requestStream()
            for await request in stream {
                let requests = await coordinator.pendingRequests()
                await MainActor.run {
                    self?.hitlPendingRequests = requests
                    if !requests.isEmpty {
                        self?.showHITLSheet = true
                    }
                }
                // **ADR-153 P1-7** — NotificationPolicyMatrix로 Telegram 전달 채널 결정.
                // .hitlApprovalRequest 가 telegramOnly / both / macOSAndTelegram → Telegram 전송.
                // suppressed / macOSOnly → 전송 생략 (macOS UserNotification만 발송됨).
                let deliveryChannel = await MainActor.run { self?.currentDeliveryChannel(for: .hitlApprovalRequest) }
                let sendViaTelegram: Bool
                switch deliveryChannel {
                case .telegramOnly, .both:
                    sendViaTelegram = true
                default:
                    sendViaTelegram = false
                }

                if sendViaTelegram, let self, let chatId = self.preferences.telegramChatId {
                    // Telegram inline button 메시지 전송 + ADR-099 P1-4: messageId 저장
                    let approveData = TelegramHITLCallbackHandler.HITLAction.approve.callbackData(for: request.id)
                    let rejectData = TelegramHITLCallbackHandler.HITLAction.reject.callbackData(for: request.id)
                    let buttons = [[
                        InlineButton(text: "✅ Approve", callbackData: approveData),
                        InlineButton(text: "❌ Reject", callbackData: rejectData)
                    ]]
                    let text = "⚠️ HITL 승인 필요\n\n**Action:** `\(request.action)`\n**Timeout:** \(request.timeoutSeconds)s"
                    if let sent = try? await self.telegramBot?.sendWithKeyboard(text, to: chatId, buttons: buttons) {
                        // ADR-099 P1-4 — messageId를 coordinator에 등록 (응답 후 edit용)
                        await coordinator.setTelegramMessageId(sent.messageId, chatId: chatId, for: request.id)
                    }
                }
                // **ADR-098 P0-4** — macOS UserNotification 동시 발송 (HITL actionable)
                try? await MacOSNotificationSender.sendHITL(
                    requestId: request.id,
                    action: request.action,
                    workspaceName: request.workspace
                )
            }
        }
    }

    /// **ADR-094 Phase 3 / ADR-099 P1-4** — 외부에서 HITL 응답 주입 (데스크탑 UI 또는 Telegram callback).
    /// 응답 후 텔레그램 메시지를 editMessageText로 자동 갱신 (승인/거절/timeout/cancelled 상태 표시).
    public func respondToHITL(id: UUID, response: TelegramHITLCoordinator.HITLResponse) async {
        // ADR-099 P1-4 — respond 전에 pending request에서 messageId/chatId 조회
        let pendingBefore = await hitlCoordinator?.pendingRequests() ?? []
        let matchedRequest = pendingBefore.first { $0.id == id }

        await hitlCoordinator?.respond(id: id, response: response)
        let requests = await hitlCoordinator?.pendingRequests() ?? []
        hitlPendingRequests = requests
        if requests.isEmpty {
            showHITLSheet = false
        }

        // ADR-099 P1-4 — HITL 응답 후 텔레그램 메시지 자동 edit
        if let req = matchedRequest,
           let msgId = req.telegramMessageId,
           let chatId = req.telegramChatId,
           let bot = telegramBot {
            await TelegramSendHelper.editHITLMessage(
                response: response,
                originalAction: req.action,
                messageId: msgId,
                chatId: chatId,
                client: bot
            )
        }

        // **ADR-115 P0-3** — reject/timeout/cancelled 시 Claude 프로세스 자동 중단.
        // Telegram 경로: bridge.consume(event:)의 onHITLCancelRequired 콜백이 cancelBoundTurn()을
        // 이미 호출하므로 여기서는 desktop-only 시나리오(bridge 없음)를 보완한다.
        // bridge가 있는 경우 cancelBoundTurn()은 자체 notifyCancelled()를 보내므로
        // 중복 알림 없이 프로세스만 추가 중단 시도한다.
        switch response {
        case .rejected, .timeout, .cancelled:
            // bridge가 없으면(desktop 단독 흐름) cancelStream()을 직접 호출해야 한다.
            // bridge가 있으면 onHITLCancelRequired 콜백이 이미 cancelBoundTurn()을 불렀으므로
            // cancelStream()은 중복 호출이지만 idempotent하므로 안전하다.
            if !isStreaming {
                break  // 이미 중단됨
            }
            cancelStream()
            // bridge가 없는 경우(desktop 단독)에만 별도 notice 불필요.
            // bridge가 있는 경우 cancelBoundTurn()→notifyCancelled() 메시지가 이미 발송됨.
        case .approved:
            break
        }
    }
}
