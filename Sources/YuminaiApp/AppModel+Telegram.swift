import Foundation
import AppKit
import os
import YuminaiCore
import YuminaiTelegram
import YuminaiPersistence

// ADR-127 — AppModel.swift 분할: Telegram 도메인
// Multi-bot 관리 + ChatSession + cokacdir + Commands + 사용량 + 상태
extension AppModel {

    // MARK: - Computed properties (Telegram domain)

    /// 현재 활성 ChatSession (preferences.activeChatSessionId 기준).
    public var activeChatSession: ChatSession? {
        guard let id = preferences.activeChatSessionId else { return nil }
        return preferences.chatSessions.first { $0.id == id }
    }

    /// 활성 워크스페이스의 agentKind (activeChatSession 우선, fallback: workspace).
    private var agentKindForActiveWorkspace: AgentKind {
        if let session = activeChatSession { return session.agentKind }
        return workspaces.first { $0.id == selectedWorkspaceId }?.agentKind ?? .default
    }

    /// 텔레그램에 바인딩된 워크스페이스 이름 (없으면 nil).
    public var boundWorkspaceName: String? {
        guard let id = preferences.telegramBoundWorkspaceId else { return nil }
        return workspaces.first { $0.id == id }?.name
    }

    // MARK: - telegram

    public func sendTelegramTest() async {
        guard let bot = telegramBot, let chatId = preferences.telegramChatId else {
            self.error = "Telegram 미설정"
            return
        }
        do {
            _ = try await bot.send("[YUMINAI TEST] 연결 성공", to: chatId)
        } catch {
            self.error = "Telegram 테스트 실패: \(error.localizedDescription)"
        }
    }

    func activateTelegramIfReady() async {
        await deactivateTelegram()
        guard preferences.telegramEnabled, let chatId = preferences.telegramChatId else {
            return
        }
        let token: String?
        do {
            token = try await keychainStore.get(KeychainKey.telegramBotToken)
        } catch {
            logger.error("Telegram token 읽기 실패: \(error.localizedDescription)")
            return
        }
        guard let token else { return }

        let bot = LiveTelegramBot(
            token: token,
            allowedUserIds: Set(preferences.telegramAllowedUserIds)
        )
        telegramBot = bot
        alertDispatcher = TelegramAlertDispatcher(
            client: bot,
            policy: preferences.telegramAlertPolicy,
            chatId: chatId
        )
        sessionBridge = await makeSessionBridge(client: bot, chatId: chatId)
        // ADR-098 P1-1 — bridge에 artifact store 주입 → diff/log 발송이 store + deep link 경로로 라우팅.
        await sessionBridge?.setArtifactStore(telegramArtifactStore)
        let router = YuminaiCommandRouter(appModel: self)
        let pump = TelegramCommandPump(client: bot, router: router)
        commandPump = pump
        do {
            try await pump.start()
            logger.info("Telegram 활성화: chatId=\(chatId)")
        } catch {
            logger.error("Telegram pump 시작 실패: \(error.localizedDescription)")
        }
        // ADR-086 Phase 1 — health snapshot observer (사이드바 pill 실시간 업데이트)
        Task { [weak self] in
            for await snapshot in await bot.healthMonitor.snapshots() {
                await MainActor.run {
                    self?.telegramHealth = snapshot
                }
            }
        }
        // ADR-093 Phase 2 — offline queue depth 5초 주기 폴링 (BotStatusDock 표시용)
        setupTelegramQueueDepthPolling()
        // ADR-094 Phase 3 — HITL coordinator 초기화 + AsyncStream 구독
        setupTelegramHITLCoordinator()
        // ADR-095 Phase 4 + ADR-098 P0-3 — deliveryChannelProvider 주입
        // (NotificationPolicyMatrix + quiet hours + deviceState 정책이 실제 alarmRouting에 반영됨)
        // 클로저는 @Sendable nonisolated이므로 MainActor.assumeIsolated로 main actor 상태에 접근.
        // TelegramAlertDispatcher.dispatch()는 항상 async context에서 호출되며,
        // dispatch 시점에 main actor 접근을 보장하는 형태로 future refactor 가능.
        if let dispatcher = alertDispatcher {
            await dispatcher.updateDeliveryChannelProvider { [weak self] kind in
                MainActor.assumeIsolated {
                    self?.currentDeliveryChannel(for: kind) ?? .telegramOnly
                }
            }
        }
    }

    /// **ADR-093 Phase 2** — Queue depth 5초 주기 폴링 Task.
    private func setupTelegramQueueDepthPolling() {
        Task { [weak self] in
            while !Task.isCancelled {
                if let depth = await self?.telegramOfflineQueueDepth() {
                    await MainActor.run {
                        self?.telegramQueueDepth = depth
                    }
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    // MARK: - ADR-086 Phase 1 — Telegram error log access

    public func telegramRecentErrors(limit: Int = 20) async -> [TelegramErrorEntry] {
        guard let bot = telegramBot as? LiveTelegramBot else { return [] }
        return await bot.errorLog.recent(limit: limit)
    }

    public func telegramErrorStats() async -> [TelegramErrorEntry.Category: Int] {
        guard let bot = telegramBot as? LiveTelegramBot else { return [:] }
        return await bot.errorLog.statsByCategory()
    }

    public func telegramClearErrorLog() async {
        guard let bot = telegramBot as? LiveTelegramBot else { return }
        await bot.errorLog.clear()
    }

    // MARK: - ADR-093 Phase 2 — Queue depth + chat activity

    /// Offline queue에 대기 중인 메시지 수 반환.
    public func telegramOfflineQueueDepth() async -> Int {
        guard let bot = telegramBot as? LiveTelegramBot else { return 0 }
        return await bot.offlineQueue.count()
    }

    /// 최근 활동 chat 목록 (chatId + lastUsedAt). BotStatusDock / ChatContextCard 표시용.
    public func telegramRecentChatActivity() async -> [(Int64, Date)] {
        let snapshot = await telegramUsageStore.snapshot()
        return snapshot.chatStats.values
            .sorted { $0.lastUsedAt > $1.lastUsedAt }
            .map { ($0.chatId, $0.lastUsedAt) }
    }

    // MARK: - ADR-086 Phase 4 — Multi-bot management

    /// 새 봇 추가 (token은 keychain에 별도 저장).
    public func addTelegramBot(_ config: TelegramBotConfig) async {
        // 중복 ID 방지
        guard !preferences.telegramBots.contains(where: { $0.id == config.id }) else { return }
        preferences.telegramBots.append(config)
        await savePreferences()
    }

    /// 봇 설정 update.
    public func updateTelegramBot(_ config: TelegramBotConfig) async {
        guard let idx = preferences.telegramBots.firstIndex(where: { $0.id == config.id }) else { return }
        preferences.telegramBots[idx] = config
        await savePreferences()
    }

    /// 봇 제거 (관련 binding 도 cascade delete).
    /// (그룹 멤버십은 TelegramBotConfig.groupId로 관리되므로 별도 cascade 불필요)
    public func removeTelegramBot(_ id: UUID) async {
        preferences.telegramBots.removeAll { $0.id == id }
        preferences.telegramBotChatBindings.removeAll { $0.botId == id }
        await savePreferences()
    }

    /// 봇을 그룹에 할당 또는 그룹에서 제거 (groupId nil = 그룹 없음).
    public func assignBot(_ botId: UUID, toGroup groupId: UUID?) async {
        guard let idx = preferences.telegramBots.firstIndex(where: { $0.id == botId }) else { return }
        preferences.telegramBots[idx].groupId = groupId
        await savePreferences()
    }

    /// 그룹 add.
    public func addTelegramBotGroup(_ group: TelegramBotGroup) async {
        guard !preferences.telegramBotGroups.contains(where: { $0.id == group.id }) else { return }
        preferences.telegramBotGroups.append(group)
        await savePreferences()
    }

    public func updateTelegramBotGroup(_ group: TelegramBotGroup) async {
        guard let idx = preferences.telegramBotGroups.firstIndex(where: { $0.id == group.id }) else { return }
        preferences.telegramBotGroups[idx] = group
        await savePreferences()
    }

    public func removeTelegramBotGroup(_ id: UUID) async {
        preferences.telegramBotGroups.removeAll { $0.id == id }
        await savePreferences()
    }

    /// Chat binding upsert (botId + chatId 조합으로 unique).
    public func upsertBotChatBinding(_ binding: BotChatBinding) async {
        if let idx = preferences.telegramBotChatBindings.firstIndex(where: {
            $0.botId == binding.botId && $0.chatId == binding.chatId
        }) {
            preferences.telegramBotChatBindings[idx] = binding
        } else {
            preferences.telegramBotChatBindings.append(binding)
        }
        await savePreferences()
    }

    public func removeBotChatBinding(_ id: UUID) async {
        preferences.telegramBotChatBindings.removeAll { $0.id == id }
        await savePreferences()
    }

    // MARK: - ADR-089 ChatSession (ad-hoc 대화) management

    /// 새 ad-hoc 대화 세션 생성 + 자동 활성화.
    /// - Parameters:
    ///   - title: 세션 제목 (예: "버그 디버깅", "리팩토링 아이디어")
    ///   - workspaceId: 어느 워크스페이스 폴더에서 실행할지. **ADR-091** — nil이면 자유 대화.
    ///   - agentKind: Claude or Codex
    ///   - settings: model + permissionMode + effort
    /// - Returns: 생성된 ChatSession id (이미 active로 설정됨).
    @discardableResult
    public func createChatSession(
        title: String,
        workspaceId: UUID? = nil,
        agentKind: AgentKind = .default,
        settings: SessionSettings = .default
    ) async -> UUID {
        let session = ChatSession(
            title: title,
            workspaceId: workspaceId,
            agentKind: agentKind,
            settings: settings
        )
        preferences.chatSessions.append(session)
        preferences.activeChatSessionId = session.id
        await savePreferences()
        return session.id
    }

    /// ChatSession 활성화 (사이드바에서 클릭).
    /// 활성화하면 그 session의 workspaceId로 transition + agentKind/settings도 swap.
    public func activateChatSession(_ id: UUID) async {
        guard let session = preferences.chatSessions.first(where: { $0.id == id }) else { return }
        preferences.activeChatSessionId = id

        // 1) workspace 전환 (필요 시) — ADR-091: workspaceId가 nil이면 자유 대화 → 전환 안 함
        if let wsId = session.workspaceId, selectedWorkspaceId != wsId {
            await transitionToWorkspace(wsId)
        }

        // 2) agent + settings 적용 (워크스페이스가 있을 때만 — 자유 대화는 settings만 메모리에 유지)
        if session.workspaceId != nil {
            if agentKindForActiveWorkspace != session.agentKind {
                await setActiveAgentKind(session.agentKind)
            }
            if activeSettings != session.settings {
                await updateActiveSettings(session.settings)
            }
        } else {
            // 자유 대화: activeSettings만 갱신 (cwd 없으므로 어댑터 spawn은 chat 모드)
            if activeSettings != session.settings {
                activeSettings = session.settings
                await claudeAdapter.updateSettings(session.settings)
            }
        }

        // 3) lastActiveAt 갱신
        if let idx = preferences.chatSessions.firstIndex(where: { $0.id == id }) {
            preferences.chatSessions[idx].lastActiveAt = Date()
        }
        await savePreferences()
    }

    /// **ADR-091** — 자유 대화에 워크스페이스 attach (또는 detach 시 nil).
    /// attach 시 그 workspace로 transition + agent settings 적용.
    public func attachChatSessionToWorkspace(_ sessionId: UUID, workspaceId: UUID?) async {
        guard let idx = preferences.chatSessions.firstIndex(where: { $0.id == sessionId }) else { return }
        preferences.chatSessions[idx].workspaceId = workspaceId
        preferences.chatSessions[idx].lastActiveAt = Date()
        await savePreferences()
        // 활성 세션이면 즉시 전환
        if preferences.activeChatSessionId == sessionId {
            await activateChatSession(sessionId)
        }
    }

    /// ChatSession 활성 해제 — 워크스페이스 main 대화로 복귀.
    public func deactivateChatSession() async {
        preferences.activeChatSessionId = nil
        await savePreferences()
    }

    /// ChatSession 제목 변경.
    public func renameChatSession(_ id: UUID, to newTitle: String) async {
        guard let idx = preferences.chatSessions.firstIndex(where: { $0.id == id }) else { return }
        preferences.chatSessions[idx].title = newTitle
        await savePreferences()
    }

    /// ChatSession 삭제 (영구).
    public func deleteChatSession(_ id: UUID) async {
        preferences.chatSessions.removeAll { $0.id == id }
        if preferences.activeChatSessionId == id {
            preferences.activeChatSessionId = nil
        }
        await savePreferences()
    }

    /// ChatSession archive 토글 (목록에서 숨김 — 영구 삭제 ≠ archive).
    public func toggleChatSessionArchive(_ id: UUID) async {
        guard let idx = preferences.chatSessions.firstIndex(where: { $0.id == id }) else { return }
        preferences.chatSessions[idx].isArchived.toggle()
        await savePreferences()
    }

    /// 최근 활성순으로 정렬된 chat sessions (archived 제외, 옵션으로 포함).
    public func recentChatSessions(includeArchived: Bool = false) -> [ChatSession] {
        let filtered = includeArchived
            ? preferences.chatSessions
            : preferences.chatSessions.filter { !$0.isArchived }
        return filtered.sorted { $0.lastActiveAt > $1.lastActiveAt }
    }

    /// bound workspace가 있을 때만 bridge 생성. 없으면 nil.
    /// **ADR-114-B** — bridge 생성 시 HITL 자동 취소 콜백을 함께 주입한다.
    /// HITL이 reject/timeout/cancelled로 끝나면 bridge가 콜백을 통해
    /// `cancelBoundTurn()`을 트리거 → 사용자가 `/cancel`을 직접 입력할 필요 없음.
    private func makeSessionBridge(client: any TelegramClient, chatId: Int64) async -> TelegramSessionBridge? {
        guard let boundId = preferences.telegramBoundWorkspaceId,
              let workspace = workspaces.first(where: { $0.id == boundId })
        else { return nil }
        let config = TelegramSessionBridge.Configuration(
            chatId: chatId,
            workspaceName: workspace.name,
            forwardAssistant: preferences.telegramForwardAssistant,
            forwardToolCalls: preferences.telegramForwardToolCalls
        )
        let bridge = TelegramSessionBridge(client: client, configuration: config)
        // ADR-114-B — 자동 취소 콜백: HITL reject/timeout/cancelled 시 호출됨.
        let cancelCallback: TelegramSessionBridge.HITLCancelCallback = { [weak self] in
            _ = await self?.cancelBoundTurn()
        }
        await bridge.setOnHITLCancelRequired(cancelCallback)
        return bridge
    }

    // MARK: - cokacdir bot import (ADR-024)

    /// cokacdir bot_settings.json + group_chat 로그를 읽어 봇 목록 + chat label을 로드.
    /// SettingsView "cokacdir에서 가져오기" 버튼이 호출.
    /// **ADR-100** — `mode`로 import 후 라우팅 분기. `.legacy`(default)는 단일 봇 슬롯, `.hub`는 multi-bot.
    /// `presentSheet`: true이면 RootView의 sheet를 띄움 (Settings 진입). false이면 데이터만 로드 (Hub처럼 자체 sheet를 띄우는 호출자용).
    public func loadCokacdirBots(mode: CokacdirImportMode = .legacy, presentSheet: Bool = true) async {
        cokacdirImportError = nil
        cokacdirChatLabels = [:]
        cokacdirImportMode = mode
        let path = AppPreferences.defaultCokacdirBotSettingsPath()
        let importer = CokacdirImporter(botSettingsPath: path)
        do {
            let bots = try await importer.loadBots()
            cokacdirBots = bots
            // chat label은 봇 목록 로드 후 background로 enrich
            let inspector = CokacdirChatInspector()
            var labels: [Int64: CokacdirChatLabel] = [:]
            for bot in bots {
                for chatId in bot.suggestedChatIds where labels[chatId] == nil {
                    labels[chatId] = await inspector.label(for: chatId, ownerUserId: bot.ownerUserId)
                }
            }
            cokacdirChatLabels = labels
            if presentSheet { showCokacdirImportSheet = true }
        } catch {
            cokacdirImportError = error.localizedDescription
            if presentSheet { showCokacdirImportSheet = true }
        }
    }

    /// **ADR-100** — cokacdir 봇을 Telegram Hub의 multi-bot 모델 (`preferences.telegramBots`)에 추가.
    /// 토큰은 봇별 keychain key (`telegram.bot.<botHash>`)에 저장.
    /// `chatId`가 nil이 아니면 binding도 함께 생성 (활성 워크스페이스 미지정).
    public func addBotFromCokacdirToHub(_ bot: CokacdirBot, chatId: Int64?) async {
        // 중복 체크 (같은 username의 봇이 이미 multi-bot 목록에 있으면 스킵)
        if !bot.username.isEmpty, preferences.telegramBots.contains(where: { $0.username == bot.username }) {
            cokacdirImportError = "봇 @\(bot.username)이 이미 Telegram Hub에 등록되어 있어요."
            return
        }
        let keychainKey = "telegram.bot.\(bot.botHash)"
        do {
            try await keychainStore.set(bot.token, for: keychainKey)
            let config = TelegramBotConfig(
                id: UUID(),
                displayName: bot.displayName,
                username: bot.username,
                keychainKey: keychainKey,
                groupId: nil,
                allowedUserIds: bot.ownerUserId != 0 ? [bot.ownerUserId] : [],
                enabled: true,
                iconName: "paperplane.circle.fill",
                colorName: "accent",
                notes: "cokacdir에서 가져옴 (botHash: \(bot.botHash.prefix(8))…)"
            )
            await addTelegramBot(config)
            // chatId 있으면 binding도 추가
            if let chatId {
                let binding = BotChatBinding(
                    id: UUID(),
                    botId: config.id,
                    chatId: chatId,
                    activeWorkspaceId: nil,
                    allowedWorkspaceIds: [],
                    nickname: ""
                )
                await upsertBotChatBinding(binding)
            }
            showCokacdirImportSheet = false
            cokacdirImportError = nil
        } catch {
            cokacdirImportError = "Hub에 봇 추가 실패: \(error.localizedDescription)"
        }
    }

    /// 선택한 cokacdir 봇의 토큰을 keychain에 저장 + chatId/허용 user 자동 설정.
    public func applyCokacdirBot(_ bot: CokacdirBot, chatId: Int64) async {
        // ADR-046 M5 — cokacdir 프로세스가 동시 실행 중이면 같은 토큰 polling 충돌 → 메시지 절반씩 분산
        // pgrep으로 검출 후 사용자에게 경고 (사용자 결정에 따라 진행 또는 취소)
        if isCokacdirRunning() {
            let alert = NSAlert()
            alert.messageText = "cokacdir이 실행 중이에요"
            alert.informativeText = "cokacdir 프로세스가 같은 텔레그램 토큰으로 polling하면 메시지가 절반씩 분산됩니다 (Telegram getUpdates는 first-poll-wins).\n\nYuminai에서 사용하기 전에 cokacdir을 종료해주세요."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "그래도 진행")
            alert.addButton(withTitle: "취소")
            if alert.runModal() != .alertFirstButtonReturn {
                cokacdirImportError = "사용자 취소: cokacdir 종료 후 다시 시도하세요."
                return
            }
        }
        do {
            try await keychainStore.set(bot.token, for: KeychainKey.telegramBotToken)
            telegramTokenStatus = .set
            preferences.telegramChatId = chatId
            preferences.telegramSourceLabel = bot.displayName
            // 봇 owner를 허용 user로 자동 추가 (없으면)
            if !preferences.telegramAllowedUserIds.contains(bot.ownerUserId) {
                preferences.telegramAllowedUserIds.append(bot.ownerUserId)
            }
            preferences.telegramEnabled = true
            await savePreferences()
            showCokacdirImportSheet = false
        } catch {
            cokacdirImportError = "토큰 저장 실패: \(error.localizedDescription)"
        }
    }

    /// ADR-046 M5 — pgrep으로 cokacdir 프로세스 검출.
    /// 실패 시 false (충돌 가능성 무시) — 사용성이 우선.
    private func isCokacdirRunning() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", "cokacdir"]  // exact match
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            // pgrep은 매치 발견 시 exit 0, 없으면 1
            return process.terminationStatus == 0
        } catch {
            // pgrep 실행 실패 (권한/path 문제) — 검출 포기
            return false
        }
    }

    func deactivateTelegram() async {
        if let pump = commandPump {
            await pump.stop()
        }
        if let bridge = sessionBridge {
            await bridge.reset()
        }
        commandPump = nil
        alertDispatcher = nil
        sessionBridge = nil
        telegramBot = nil
    }

    // MARK: - Telegram session control (ADR-025)

    /// 워크스페이스를 텔레그램 제어 대상으로 설정. nil이면 해제.
    /// ADR-045 R2.H3 — defaultChatId 인자: bind 호출한 chat을 자동으로 응답 default chat으로.
    /// Telegram 봇이 활성화돼 있으면 bridge를 즉시 갱신.
    public func bindTelegramWorkspace(_ id: UUID?, defaultChatId: Int64? = nil) async {
        preferences.telegramBoundWorkspaceId = id
        // bind 호출한 chat을 default response chat으로 (multi-chat 시 가장 자연스러움)
        if let defaultChatId, id != nil {
            preferences.telegramChatId = defaultChatId
        }
        await savePreferences()

        // bridge 재구성
        if let bot = telegramBot, let chatId = preferences.telegramChatId {
            if let bridge = sessionBridge {
                await bridge.reset()
            }
            sessionBridge = await makeSessionBridge(client: bot, chatId: chatId)
            // ADR-098 P1-1 — 재구성된 bridge에도 artifact store 주입 유지.
            await sessionBridge?.setArtifactStore(telegramArtifactStore)
            if let bridge = sessionBridge, let name = boundWorkspaceName {
                await bridge.sendNotice("✓ 텔레그램 연결됨 — 워크스페이스 '\(name)'")
            } else if id == nil {
                await sessionBridge?.sendNotice("연결 해제됨")
            }
        }
    }

    /// ADR-045 R2.H3 — bridge에 외부 request chat_id 설정 (multi-chat).
    public func setBridgeRequestChatId(_ chatId: Int64) async {
        await sessionBridge?.setRequestChatId(chatId)
    }

    /// ADR-046 — 외부 turn 시작 시 plan-mode 강제 (preferences.telegramRemoteRequiresPlan=true 시).
    /// 반환: 복원할 원래 설정 (nil이면 강제 안 함). caller가 turn 종료 후 scheduleSettingsRestore 호출.
    public func applyRemotePlanModeIfNeeded() -> SessionSettings? {
        guard preferences.telegramRemoteRequiresPlan else { return nil }
        let original = activeSettings
        guard original.permissionMode != .plan else { return nil }  // 이미 plan
        // plan mode로 1 turn 강제
        var planned = original
        planned.permissionMode = .plan
        activeSettings = planned
        // bridge에 사용자 안내
        let bridgeRef = sessionBridge
        Task {
            await bridgeRef?.sendNotice("🛡 외부 turn — Plan 모드로 실행됩니다. 결과 확인 후 '진행해 줘'로 승인하세요.\n(설정에서 `telegramRemoteRequiresPlan` 끄면 비활성화)")
        }
        return original
    }

    /// 외부 turn 종료 후 settings 복원 (turn 1개 후).
    public func scheduleSettingsRestore(_ original: SessionSettings) async {
        // 다음 .completed 이벤트 후 복원 — 단순화: 짧은 delay 후 복원 (race 가능성 낮음)
        // 더 정확한 방법: turn id 추적 후 정확히 그 turn 끝에서 복원. v2.0+에서 검토.
        Task { @MainActor in
            // 활성 turn이 끝날 때까지 대기 (max 5분)
            let start = Date()
            while isStreaming, Date().timeIntervalSince(start) < 300 {
                try? await Task.sleep(for: .milliseconds(500))
            }
            // 복원
            self.activeSettings = original
        }
    }

    public func incrementExternalTurnCount() {
        externalTurnCount += 1
        // ADR-055 HIGH 4 — turn 시작 시 cost snapshot
        externalTurnStartCostSnapshot = currentSessionUsage.costUSD
        isExternalTurn = true
    }

    /// **ADR-062 Phase 6** — Telegram turn 시작/종료 시 usage store 기록 helper.
    /// **ADR-063 Phase 5** — workspaceId 전달 (chat별 workspace 분포 분석).
    public func recordTelegramTurnStart(chatId: Int64) async {
        let wsId = selectedWorkspaceId
        await telegramUsageStore.recordTurnStart(chatId: chatId, workspaceId: wsId)
        telegramUsageSnapshot = await telegramUsageStore.snapshot()
    }

    public func recordTelegramTurnComplete(chatId: Int64, costUSD: Double, inputTokens: Int, outputTokens: Int) async {
        await telegramUsageStore.recordTurnComplete(
            chatId: chatId,
            costUSD: costUSD,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
        telegramUsageSnapshot = await telegramUsageStore.snapshot()
        // ADR-067 Phase 3 — anomaly auto-alert (cooldown 1h)
        await maybeAnomalyAlert()
    }

    public func recordTelegramCommand(_ command: String) async {
        await telegramUsageStore.recordCommand(command)
        telegramUsageSnapshot = await telegramUsageStore.snapshot()
    }

    /// bootstrap에서 호출.
    public func loadTelegramUsage() async {
        telegramUsageSnapshot = await telegramUsageStore.snapshot()
        telegramDailyBuckets = await telegramUsageStore.dailyAggregation()
    }

    /// **ADR-062 Phase 6** — Telegram 통계 초기화.
    public func clearTelegramUsage() async {
        await telegramUsageStore.clear()
        telegramUsageSnapshot = await telegramUsageStore.snapshot()
    }

    /// **ADR-067 Phase 3** — anomaly auto-alert (turn 종료 시 호출).
    /// 누적 hourly cost가 anomaly threshold 초과면 Telegram bridge로 push.
    /// 같은 anomaly type은 1시간 내 1회만 (alert spam 방지).
    public func maybeAnomalyAlert() async {
        // bound bridge 있어야 alert 가능
        guard let bridge = sessionBridge else { return }
        // 1시간 cooldown
        if let last = lastAnomalyAlertAt, Date().timeIntervalSince(last) < 3600 {
            return
        }
        let costs = telegramUsageSnapshot.hourlyBuckets.map(\.costUSD)
        guard costs.count >= 3 else { return }
        let threshold = preferences.anomalyZScoreThreshold
        let anomalies = UsageForecaster.detectAnomalies(costs, threshold: threshold)
        // 가장 최근 sample이 anomaly인지 (마지막 index)
        let lastIdx = costs.count - 1
        guard let recentAnomaly = anomalies.first(where: { $0.index == lastIdx }) else {
            return
        }
        let direction = recentAnomaly.direction == .high ? "🚨 spike" : "🔻 drop"
        let msg = """
        \(direction) anomaly 감지!
          · 최근 1시간 cost: $\(String(format: "%.4f", recentAnomaly.value))
          · z-score: \(String(format: "%.2f", recentAnomaly.zScore)) (threshold \(String(format: "%.1f", threshold)))
          · /cost로 자세히 확인
        """
        Task { await bridge.sendNotice(msg) }
        lastAnomalyAlertAt = Date()
    }

    /// **ADR-062 Phase 6** — chatId → workspace name (UI 라벨용).
    public func telegramChatIdToWorkspaceName() -> [String: String] {
        var result: [String: String] = [:]
        for (chatKey, wsId) in preferences.telegramChatBindings {
            if let ws = workspaces.first(where: { $0.id == wsId }) {
                result[chatKey] = ws.name
            }
        }
        return result
    }

    /// /status 명령에 응답할 텍스트 생성. ADR-045 R2.H5 — 외부 turn 비용 + context % 가시화.
    public func telegramStatusSnapshot() -> String {
        let bound = boundWorkspaceName ?? "없음"
        let active = workspaces.first { $0.id == selectedWorkspaceId }?.name ?? "없음"
        let streamingTag = isStreaming ? "응답 중" : "대기 중"
        let ctxPct = Int(currentContextUsage * 100)
        let ctxWarn = ctxPct >= 70 ? " ⚠" : ""
        let costStr = String(format: "$%.4f", currentSessionUsage.costUSD)
        let externalCostStr = String(format: "$%.4f", externalTurnTotalCostUSD)
        var lines = [
            "현재 상태:",
            "  · 연결된 워크스페이스: \(bound)",
            "  · 활성 워크스페이스: \(active)",
            "  · Claude: \(streamingTag)",
            "  · 모델: \(activeSettings.model.displayName)",
            "  · 컨텍스트: \(ctxPct)%\(ctxWarn)",
            "  · 현재 세션 비용: \(costStr)",
            "  · 외부 turn 횟수: \(externalTurnCount) (누적 \(externalCostStr))"
        ]
        if ctxPct >= 70 {
            lines.append("")
            lines.append("⚠ 컨텍스트가 70%를 넘어 새 세션을 시작하는 것이 좋아요.")
        }
        return lines.joined(separator: "\n")
    }

    /// bound 세션의 진행 중 turn 중단. 중단됐으면 true.
    public func cancelBoundTurn() async -> Bool {
        guard isStreaming,
              let bound = preferences.telegramBoundWorkspaceId,
              selectedWorkspaceId == bound
        else { return false }
        cancelStream()
        if let bridge = sessionBridge {
            await bridge.notifyCancelled()
        }
        return true
    }

    // MARK: - ADR-094 Phase 3 — TelegramCommand management

    /// 커맨드 목록 전체 교체.
    public func updateTelegramCommands(_ commands: [TelegramCommand]) async {
        preferences.telegramCommands = commands
        await savePreferences()
    }

    /// 커맨드 추가 (중복 ID 방지).
    public func addTelegramCommand(_ command: TelegramCommand) async {
        guard !preferences.telegramCommands.contains(where: { $0.id == command.id }) else { return }
        preferences.telegramCommands.append(command)
        await savePreferences()
    }

    /// 커맨드 업데이트.
    public func updateTelegramCommand(_ command: TelegramCommand) async {
        guard let idx = preferences.telegramCommands.firstIndex(where: { $0.id == command.id }) else { return }
        preferences.telegramCommands[idx] = command
        await savePreferences()
    }

    /// 커맨드 제거.
    public func removeTelegramCommand(id: UUID) async {
        preferences.telegramCommands.removeAll { $0.id == id }
        await savePreferences()
    }

    /// **ADR-094 Phase 3** — enabled 커맨드를 BotFather에 동기화.
    /// - Returns: `.success(등록수)` 또는 `.failure(error)`
    public func syncTelegramCommandsToBotFather() async -> Result<Int, any Error> {
        guard let bot = telegramBot else {
            return .failure(NSError(domain: "AppModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "봇이 활성화되어 있지 않습니다"]))
        }

        let enabled = preferences.telegramCommands.filter { $0.enabled && $0.isValidTrigger && $0.isValidDescription }
        let pairs = enabled.map { (command: $0.apiCommand, description: $0.description) }

        do {
            try await bot.setMyCommands(pairs)
            return .success(pairs.count)
        } catch {
            return .failure(error)
        }
    }
}
