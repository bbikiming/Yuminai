import Foundation
import YuminaiCore
import YuminaiTelegram

/// Telegram에서 받은 메시지를 워크스페이스 채팅에 전달하는 라우터.
///
/// 명령어:
/// - `/bind <name>` — 이름이 일치하는 워크스페이스를 텔레그램 제어 대상으로 설정
/// - `/unbind` — 연결 해제
/// - `/status` — 현재 bind 상태 + 진행 표시
/// - `/cancel`, `/stop` — 진행 중인 Claude turn 중단
/// - `/list` — 워크스페이스 목록
/// - `/help` — 명령 목록
///
/// prefix 없는 일반 텍스트 → bound 워크스페이스의 입력으로 전송 (없으면 안내)
public final class YuminaiCommandRouter: TelegramCommandRouter, @unchecked Sendable {
    weak var appModel: AppModel?

    public init(appModel: AppModel) {
        self.appModel = appModel
    }

    public func handle(_ message: IncomingTelegramMessage) async -> String? {
        // ADR-045 R1.H4 — bot reflection 차단 (allowlist 통과해도 추가 가드)
        guard !message.isFromBot else { return nil }
        // ADR-056 Phase 2 — callback_query (inline keyboard 클릭) 처리
        if let cb = message.callbackData {
            return await handleCallback(cb, requestChatId: message.chatId)
        }
        guard let raw = message.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else {
            return nil
        }

        if raw.hasPrefix("/") {
            return await handleCommand(raw, requestChatId: message.chatId)
        }
        return await handlePlainText(raw, requestChatId: message.chatId)
    }

    /// **ADR-056 Phase 2** — inline keyboard callback handler.
    /// callbackData 형식: "cmd:arg" (예: "cancel" / "diff" / "task:run:<uuid>" / "rehearse:<taskId>:claude")
    private func handleCallback(_ data: String, requestChatId: Int64) async -> String? {
        let parts = data.split(separator: ":", maxSplits: 2).map(String.init)
        guard let command = parts.first else { return nil }
        switch command {
        case "cancel":
            return await cancelCommand()
        case "diff":
            return await diffCommand()
        case "status":
            return await statusCommand()
        case "cost":
            return await costCommand()
        case "task" where parts.count >= 3 && parts[1] == "run":
            return await runTaskByIdCommand(parts[2])
        case "rehearse" where parts.count >= 3:
            // rehearse:<taskId>:<claude|codex>
            let taskId = parts[1]
            let agentRaw = parts[2]
            return await rehearseCommand("\(taskId) \(agentRaw)")
        default:
            return "알 수 없는 callback: \(data)"
        }
    }

    // MARK: - Commands

    private func handleCommand(_ text: String, requestChatId: Int64) async -> String? {
        let split = text.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let cmd = split[0].lowercased()
        let arg = split.count > 1
            ? String(split[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""

        switch cmd {
        case "/bind":
            return await bindCommand(arg, requestChatId: requestChatId)
        case "/unbind":
            return await unbindCommand()
        case "/status":
            return await statusCommand()
        case "/cancel", "/stop":
            return await cancelCommand()
        case "/start":
            // ADR-045 R1.L6 — onboarding (Telegram convention: /start은 권한 안내)
            return await startCommand(requestChatId: requestChatId)
        case "/help":
            return Self.helpText
        case "/list", "/workspaces":
            return await listWorkspaces()
        case "/use", "/switch":
            // ADR-045 — workspace 활성 전환 (bind 유지)
            return await useCommand(arg)
        case "/diff":
            // ADR-045 — pendingDiff chunked 전송
            return await diffCommand()
        case "/changes":
            // ADR-045 — 변경 파일 목록만
            return await changesCommand()
        case "/model":
            // ADR-048 Phase 3.C — manual model override (claude/codex)
            return await modelCommand(arg)
        case "/decompose":
            // ADR-049 Phase 4 — 사용자 큰 task LLM 자동 분해
            return await decomposeCommand(arg)
        case "/cost":
            // ADR-055 #6 — 5 buckets 비용 분리 표시
            return await costCommand()
        case "/budget":
            // ADR-055 #6 — 일일 cost cap 설정 (보호)
            return await budgetCommand(arg)
        case "/tasks":
            // ADR-056 Phase 6 — TaskGraph 조회 + 실행 (inline keyboard로 ▶ 실행)
            return await tasksCommand()
        case "/walkthrough":
            // ADR-056 Phase 6 — 완료 task의 walk-through (외부 회고)
            return await walkthroughCommand(arg)
        case "/rehearse":
            // ADR-056 Phase 6 — 다른 모델로 리허설 launch
            return await rehearseCommand(arg)
        default:
            return "알 수 없는 명령: \(cmd)\n/help로 사용 가능한 명령을 확인해요."
        }
    }

    private func bindCommand(_ name: String, requestChatId: Int64) async -> String? {
        guard !name.isEmpty else {
            return "사용법: /bind <워크스페이스 이름 또는 일부>\n예: /bind 작업폴더A\n\n/list로 전체 목록 확인"
        }
        guard let model = appModel else { return "Yuminai 연결 안 됨" }

        let match: Workspace? = await MainActor.run {
            let lower = name.lowercased()
            if let exact = model.workspaces.first(where: { $0.name.lowercased() == lower }) {
                return exact
            }
            return model.workspaces.first { $0.name.lowercased().contains(lower) }
        }

        guard let workspace = match else {
            return "‘\(name)’과 일치하는 워크스페이스가 없어요. /list로 확인해주세요."
        }

        // ADR-045 R2.H3 — bind한 chat을 자동으로 default response chat으로 설정
        // ADR-058 Phase 3 — chat-specific binding도 동시 등록 (multi-chat 지원)
        await model.bindTelegramWorkspace(workspace.id, defaultChatId: requestChatId)
        await MainActor.run {
            model.preferences.telegramChatBindings[String(requestChatId)] = workspace.id
        }
        await model.savePreferences()
        return "✓ ‘\(workspace.name)’에 이 chat 연결됐어요. (chat ID \(requestChatId) ↔ \(workspace.name))\n다른 chat에서 다른 워크스페이스를 binding하면 멀티 chat 운영 가능."
    }

    private func unbindCommand() async -> String? {
        guard let model = appModel else { return "Yuminai 연결 안 됨" }
        let prevName = await MainActor.run { model.boundWorkspaceName }
        await model.bindTelegramWorkspace(nil)
        // ADR-058 Phase 3 — chat-specific binding도 모두 해제
        await MainActor.run {
            model.preferences.telegramChatBindings.removeAll()
        }
        await model.savePreferences()
        if let prevName {
            return "✓ ‘\(prevName)’ 연결 해제. (모든 chat-specific binding도 함께 해제)"
        }
        return "이미 연결된 워크스페이스가 없어요."
    }

    private func statusCommand() async -> String? {
        guard let model = appModel else { return "Yuminai 연결 안 됨" }
        let snapshot = await MainActor.run { model.telegramStatusSnapshot() }
        return snapshot
    }

    private func cancelCommand() async -> String? {
        guard let model = appModel else { return "Yuminai 연결 안 됨" }
        let cancelled = await model.cancelBoundTurn()
        return cancelled ? "🛑 진행 중인 turn 중단됨" : "진행 중인 turn이 없어요."
    }

    private func listWorkspaces() async -> String? {
        guard let model = appModel else { return "Yuminai 연결 안 됨" }
        let names: [String] = await MainActor.run {
            let bound = model.preferences.telegramBoundWorkspaceId
            let active = model.selectedWorkspaceId
            return model.workspaces.map { ws in
                let bind = ws.id == bound ? "✈" : " "
                let star = ws.id == active ? "★" : " "
                return "\(bind)\(star) \(ws.name)"
            }
        }
        if names.isEmpty {
            return "아직 워크스페이스가 없어요. Yuminai에서 만든 후 다시 시도해주세요."
        }
        return "워크스페이스 목록:\n" + names.joined(separator: "\n") + "\n\n✈ = 텔레그램 연결됨, ★ = 현재 PC 활성"
    }

    /// ADR-045 R1.L6 — onboarding 명령. chat_id, allowlist 안내.
    private func startCommand(requestChatId: Int64) async -> String? {
        guard let model = appModel else { return "Yuminai 연결 안 됨" }
        let workspaceCount = await MainActor.run { model.workspaces.count }
        return """
        👋 Yuminai에 연결됐어요.

        이 chat 정보:
        • Chat ID: `\(requestChatId)`
        • 사용 가능한 워크스페이스: \(workspaceCount)개

        시작하기:
        1. /list — 워크스페이스 목록 확인
        2. /bind <이름> — 이 chat을 워크스페이스에 연결
        3. 일반 텍스트 입력 → Claude로 전달

        주의:
        • 외부에서 보낸 명령은 PC confirmation 없이 실행돼요
        • 위험한 작업 (rm -rf, git reset 등)은 🚨 알림과 함께 표시되니 /cancel 보낼 준비
        • 외부 turn은 PC와 같은 컨텍스트 사용 — 비용 누적 (/status로 확인)

        전체 명령: /help
        """
    }

    /// ADR-045 — workspace 활성 전환 (bind는 유지). 텔레그램에서 다른 워크스페이스 보고 싶을 때.
    private func useCommand(_ name: String) async -> String? {
        guard !name.isEmpty else {
            return "사용법: /use <워크스페이스 이름 또는 일부>\n현재 활성 워크스페이스만 변경 (bind는 유지)\n/list로 목록 확인"
        }
        guard let model = appModel else { return "Yuminai 연결 안 됨" }
        let match: Workspace? = await MainActor.run {
            let lower = name.lowercased()
            if let exact = model.workspaces.first(where: { $0.name.lowercased() == lower }) {
                return exact
            }
            return model.workspaces.first { $0.name.lowercased().contains(lower) }
        }
        guard let workspace = match else {
            return "‘\(name)’과 일치하는 워크스페이스가 없어요. /list로 확인해주세요."
        }
        await model.selectWorkspace(workspace.id)
        return "★ 활성 변경: ‘\(workspace.name)’ (bind는 그대로 유지)"
    }

    /// ADR-045 M8 — pending diff를 chunked로 전송 (code block 보존).
    private func diffCommand() async -> String? {
        guard let model = appModel else { return "Yuminai 연결 안 됨" }
        let diff = await MainActor.run { model.pendingDiff }
        let trimmed = diff.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "현재 보류 중인 diff가 없어요. agent가 파일을 수정하면 여기서 볼 수 있어요."
        }
        // 4KB cap (텔레그램 4096자 + code block 마진)
        let cap = 3500
        if trimmed.count > cap {
            let head = String(trimmed.prefix(cap))
            return "```diff\n\(head)\n```\n\n... (앞부분 \(cap)자 — 전체는 PC에서 확인하세요)"
        }
        return "```diff\n\(trimmed)\n```"
    }

    /// ADR-048 Phase 3.C — manual model override.
    /// /model claude / /model codex / /model auto / /model status
    private func modelCommand(_ arg: String) async -> String? {
        guard let model = appModel else { return "Yuminai 연결 안 됨" }
        let lower = arg.lowercased()
        if lower.isEmpty || lower == "status" {
            let active = await MainActor.run { model.currentWorkspace?.agentKind.shortLabel ?? "?" }
            let routing = await MainActor.run { model.preferences.harnessAutoRoutingEnabled ? "auto ON" : "auto OFF" }
            return "현재 모델: \(active)\nHarness routing: \(routing)\n\n사용법:\n/model claude — Claude로 전환\n/model codex — Codex로 전환\n/model auto — 자동 routing 토글"
        }
        if lower == "auto" {
            let newValue = await MainActor.run { () -> Bool in
                model.preferences.harnessAutoRoutingEnabled.toggle()
                return model.preferences.harnessAutoRoutingEnabled
            }
            await model.savePreferences()
            return "Harness 자동 routing: \(newValue ? "✓ 켜짐" : "꺼짐")"
        }
        // claude/codex 전환
        guard let kind = AgentKind(rawValue: lower) ?? AgentKind.allCases.first(where: { $0.shortLabel.lowercased() == lower }) else {
            return "알 수 없는 모델: ‘\(arg)’\n사용 가능: claude, codex, auto"
        }
        let switched = await model.switchToPaneOfKind(kind)
        if switched {
            return "✓ \(kind.shortLabel) pane으로 전환됨"
        }
        return "‘\(kind.shortLabel)’ pane이 없어요. PC에서 +로 pane 추가 후 재시도."
    }

    /// **ADR-055 #6** — 5 buckets cost 분리 표시 (격리 호출 비용 가시화).
    /// 사용법: /cost — 모든 bucket의 누적 비용 + total
    private func costCommand() async -> String? {
        guard let model = appModel else { return "Yuminai 연결 안 됨" }
        let snapshot = await MainActor.run { model.costTracker.snapshot() }
        let externalTotal = await MainActor.run { model.externalTurnTotalCostUSD }
        let externalCount = await MainActor.run { model.externalTurnCount }
        return """
        💰 Cost 분리 (현재 세션 누적):

          · Main (사용자 conversation): $\(String(format: "%.4f", snapshot.main))
          · Decomposition (격리 호출):  $\(String(format: "%.4f", snapshot.decomposition))
          · Rehearsal (다른 모델 재실행): $\(String(format: "%.4f", snapshot.rehearsal))
          · Parallel (병렬 두 번째 pane): $\(String(format: "%.4f", snapshot.parallel))
          · Routing (분류 호출):         $\(String(format: "%.4f", snapshot.routing))
          ─────────────────────
          · Total: $\(String(format: "%.4f", snapshot.total))

        외부 turn (Telegram): \(externalCount)회 / $\(String(format: "%.4f", externalTotal))

        💡 격리 호출 (decomp/rehearsal/parallel)은 메인 cache 0 영향 — 단,
        실제 비용은 발생. /budget으로 일일 cap 설정 권장.
        """
    }

    /// **ADR-055 #6 + ADR-056 Phase 4** — per-turn + per-day cost cap.
    /// /budget                    — 현재 status
    /// /budget turn <USD|off>     — per-turn cap (LiveClaudeAdapter --max-budget-usd)
    /// /budget day <USD|off>      — per-day cap (외부 turn 차단)
    /// /budget <USD>              — backward compat: per-turn cap
    private func budgetCommand(_ arg: String) async -> String? {
        guard let model = appModel else { return "Yuminai 연결 안 됨" }
        let parts = arg.split(separator: " ").map(String.init)

        if parts.isEmpty {
            // 현재 두 cap 모두 표시
            let perTurn = await MainActor.run { model.preferences.defaultSessionSettings.maxBudgetUSD }
            let perDay = await MainActor.run { model.preferences.dailyBudgetUSD }
            let snapshot = await MainActor.run { model.costTracker.snapshot() }
            let todayCost = await MainActor.run { model.todayCostUSD }
            let dayPct = perDay.map { Int(todayCost / $0 * 100) } ?? 0
            return """
            💼 Budget status:
              · per-turn cap: \(perTurn.map { "$\(String(format: "%.4f", $0))" } ?? "(미설정)")
              · per-day cap:  \(perDay.map { "$\(String(format: "%.4f", $0))" } ?? "(미설정)") (오늘 \(dayPct)%)
              · 오늘 사용: $\(String(format: "%.4f", todayCost))
              · 세션 total: $\(String(format: "%.4f", snapshot.total))

            사용법:
              /budget turn <USD>  — per-turn cap (LLM에 직접 전달)
              /budget day <USD>   — per-day cap (외부 turn 차단)
              /budget turn off    — per-turn cap 해제
              /budget day off     — per-day cap 해제
            """
        }

        // /budget turn|day <value>
        if parts.count >= 2 {
            let scope = parts[0].lowercased()
            let value = parts[1].lowercased()
            switch scope {
            case "turn":
                if value == "off" {
                    await MainActor.run { model.preferences.defaultSessionSettings.maxBudgetUSD = nil }
                    await model.savePreferences()
                    return "💼 per-turn cap 해제됨."
                }
                guard let v = Double(value), v > 0 else { return "잘못된 값: ‘\(value)’" }
                await MainActor.run { model.preferences.defaultSessionSettings.maxBudgetUSD = v }
                await model.savePreferences()
                return "💼 per-turn cap: $\(String(format: "%.4f", v)). 다음 spawn부터."
            case "day":
                if value == "off" {
                    await MainActor.run { model.preferences.dailyBudgetUSD = nil }
                    await model.savePreferences()
                    return "💼 per-day cap 해제됨."
                }
                guard let v = Double(value), v > 0 else { return "잘못된 값: ‘\(value)’" }
                await MainActor.run { model.preferences.dailyBudgetUSD = v }
                await model.savePreferences()
                return "💼 per-day cap: $\(String(format: "%.4f", v))/일 (자정 reset). 도달 시 외부 turn 차단."
            default:
                break
            }
        }

        // backward compat: /budget <USD>  → per-turn
        let single = parts[0].lowercased()
        if single == "off" {
            await MainActor.run { model.preferences.defaultSessionSettings.maxBudgetUSD = nil }
            await model.savePreferences()
            return "💼 per-turn cap 해제됨. (per-day 별도)"
        }
        guard let value = Double(single), value > 0 else {
            return "잘못된 값: ‘\(single)’\n사용법: /budget turn <USD> / /budget day <USD>"
        }
        await MainActor.run { model.preferences.defaultSessionSettings.maxBudgetUSD = value }
        await model.savePreferences()
        return "💼 per-turn cap: $\(String(format: "%.4f", value)) (per-day는 별도 — /budget day <USD>)"
    }

    /// **ADR-056 Phase 6 + ADR-058 Phase 4** — TaskGraph 조회 (inline keyboard로 ▶ 실행).
    /// inline keyboard는 별도 send (router는 텍스트만 반환하므로 keyboard는 직접 client 사용)
    private func tasksCommand() async -> String? {
        guard let model = appModel else { return "Yuminai 연결 안 됨" }
        let tasks = await MainActor.run { model.harness.tasks }
        guard !tasks.isEmpty else {
            return "현재 task가 없어요. /decompose <설명> 으로 task 추가하세요."
        }
        var lines = ["📋 TaskGraph (\(tasks.count)):"]
        for (i, task) in tasks.enumerated() {
            let icon: String = {
                switch task.status {
                case .pending: return "⏳"
                case .running: return "▶️"
                case .completed: return "✅"
                case .failed: return "❌"
                }
            }()
            let agent = task.assignedAgent?.shortLabel ?? "?"
            lines.append("\(i + 1). \(icon) [\(agent)] \(task.title)")
        }
        lines.append("")
        lines.append("/rehearse <번호> <claude|codex> — 다른 모델로 리허설")
        lines.append("/walkthrough <번호> — 완료 task의 진행 과정 회고")
        // ADR-058 Phase 4 — 사용자에게 inline keyboard 첨부 안내 (실제 button은 별도 trigger)
        lines.append("")
        lines.append("💡 ready task가 있으면 자동 ▶ 버튼 첨부 메시지가 별도로 전송됩니다 (PC bridge 활성 시)")
        // 별도 actor 호출은 router 현재 구조에서 어려움 → AppModel이 task push 시 keyboard 사용
        // 향후 router를 client-aware로 확장 시 직접 sendWithKeyboard 호출
        return lines.joined(separator: "\n")
    }

    /// **ADR-056 Phase 6** — task 번호 → 실행 (active session으로 dispatch).
    private func runTaskByIdCommand(_ idStr: String) async -> String? {
        guard let model = appModel,
              let uuid = UUID(uuidString: idStr) else {
            return "잘못된 task ID: \(idStr)"
        }
        await model.runHarnessTask(uuid)
        return "▶ task 실행 시작"
    }

    /// **ADR-056 Phase 6** — 완료 task의 walk-through 텍스트 응답.
    private func walkthroughCommand(_ arg: String) async -> String? {
        guard let model = appModel else { return "Yuminai 연결 안 됨" }
        guard !arg.isEmpty else {
            return "사용법: /walkthrough <task 번호>\n/tasks로 번호 확인."
        }
        guard let idx = Int(arg) else {
            return "task 번호는 숫자로: /walkthrough 1"
        }
        let task: HarnessTask? = await MainActor.run {
            let tasks = model.harness.tasks
            guard idx >= 1 && idx <= tasks.count else { return nil }
            return tasks[idx - 1]
        }
        guard let t = task else {
            return "task #\(idx)를 찾을 수 없어요."
        }
        let entries: [ConversationEntry] = await MainActor.run {
            let log = model.harness.conversationLog
            if !t.entryRefs.isEmpty {
                return log.filter { t.entryRefs.contains($0.id) }
            }
            return log.filter { $0.timestamp >= t.createdAt }
        }
        if entries.isEmpty {
            return "[\(t.title)] 진행 entry가 없어요. (status=\(t.status.rawValue))"
        }
        var lines = ["📖 Walk-through — \(t.title) (status=\(t.status.rawValue))"]
        for (i, entry) in entries.enumerated() {
            let role: String = {
                switch entry.role {
                case .user: return "👤"
                case .agent: return "🤖[\(entry.agentKind?.shortLabel ?? "?")]"
                case .system: return "ℹ️"
                }
            }()
            let snippet = String(entry.content.prefix(150))
            lines.append("\nStep \(i + 1) \(role)\n\(snippet)\(entry.content.count > 150 ? "…" : "")")
        }
        if let output = t.output, !output.isEmpty {
            lines.append("\n\n📤 결과: \(output.prefix(300))")
        }
        return lines.joined(separator: "\n")
    }

    /// **ADR-056 Phase 6** — 완료 task를 다른 모델로 리허설.
    /// 사용법: /rehearse <task번호> <claude|codex>
    private func rehearseCommand(_ arg: String) async -> String? {
        guard let model = appModel else { return "Yuminai 연결 안 됨" }
        let parts = arg.split(separator: " ").map(String.init)
        guard parts.count >= 2,
              let idx = Int(parts[0]) else {
            return "사용법: /rehearse <task번호> <claude|codex>\n예: /rehearse 1 codex\n/tasks로 번호 확인."
        }
        let agentStr = parts[1].lowercased()
        guard let agent = AgentKind(rawValue: agentStr) ?? AgentKind.allCases.first(where: { $0.shortLabel.lowercased() == agentStr }) else {
            return "알 수 없는 모델: ‘\(parts[1])’\n사용 가능: claude, codex"
        }
        let taskId: UUID? = await MainActor.run {
            let tasks = model.harness.tasks
            guard idx >= 1 && idx <= tasks.count else { return nil }
            return tasks[idx - 1].id
        }
        guard let id = taskId else {
            return "task #\(idx)를 찾을 수 없어요."
        }
        await model.launchRehearsal(taskId: id, agent: agent)
        return "🔄 리허설 시작 — \(agent.shortLabel) (결과는 자동 forward)"
    }

    /// ADR-049 Phase 4 — 큰 task를 LLM 호출로 sub-task 분해.
    /// 사용법: /decompose <설명>
    private func decomposeCommand(_ arg: String) async -> String? {
        guard !arg.isEmpty else {
            return "사용법: /decompose <작업 설명>\n예: /decompose 로그인 페이지 만들고 인증 API 연동\n→ Claude가 sub-task로 분해해서 task graph에 추가."
        }
        guard let model = appModel else { return "Yuminai 연결 안 됨" }
        let _ = await model.decomposeUserTask(arg)
        return "📊 작업 분해 요청 전송됨. 잠시 후 응답 + task graph 업데이트가 오면 표시됩니다.\n응답이 JSON 형식이 아니면 일반 메시지로 처리되니 명확한 분해 요청이 좋아요."
    }

    /// ADR-045 M8 — 변경 파일 목록만 (요약).
    private func changesCommand() async -> String? {
        guard let model = appModel else { return "Yuminai 연결 안 됨" }
        let changes = await MainActor.run { model.pendingChanges }
        guard !changes.isEmpty else {
            return "현재 보류 중인 변경 파일이 없어요."
        }
        let lines = changes.map { ch in
            "\(ch.status.label) \(ch.path)"
        }.joined(separator: "\n")
        return "변경 파일 (\(changes.count)개):\n```\n\(lines)\n```\n\n전체 diff는 /diff로 확인."
    }

    // MARK: - Plain text → bound session

    private func handlePlainText(_ text: String, requestChatId: Int64) async -> String? {
        guard let model = appModel else { return "Yuminai 연결 안 됨" }

        let preflight: Preflight = await MainActor.run {
            // ADR-058 Phase 3 — chat별 binding 우선 (multi-chat 지원)
            // 1. chat-specific binding 먼저 확인
            // 2. 없으면 telegramBoundWorkspaceId fallback (legacy 1:1)
            let chatKey = String(requestChatId)
            let boundId: UUID? = model.preferences.telegramChatBindings[chatKey]
                ?? model.preferences.telegramBoundWorkspaceId
            guard let id = boundId else { return .notBound }
            guard model.workspaces.contains(where: { $0.id == id }) else {
                return .boundMissing
            }
            return .ready(id, needsSwitch: model.selectedWorkspaceId != id)
        }

        switch preflight {
        case .notBound:
            return "먼저 /bind <워크스페이스 이름>으로 세션을 연결해주세요. /list로 목록 확인."
        case .boundMissing:
            return "연결된 워크스페이스를 찾을 수 없어요. /unbind 후 다시 /bind 해주세요."
        case .ready(let boundId, let needsSwitch):
            // ADR-056 Phase 4 + ADR-057 Critical Fix 4 — atomic reserve (race 방지)
            // 동시 외부 turn 2개면 두 번째는 첫 번째의 reserve 포함 합계로 cap check
            let reserved = await MainActor.run { model.tryReserveDailyBudget() }
            if !reserved {
                let cap = await MainActor.run { model.preferences.dailyBudgetUSD ?? 0 }
                let used = await MainActor.run { model.todayCostUSD }
                return """
                💼 오늘 budget cap 도달 — 외부 turn 차단됨.
                  · cap: $\(String(format: "%.4f", cap))
                  · 사용: $\(String(format: "%.4f", used))
                  · 자정에 자동 reset / 또는 /budget day off로 해제 / /budget day <USD>로 증액
                """
            }
            if needsSwitch {
                await model.selectWorkspace(boundId)
            }
            // ADR-045 R2.H3 — 응답 destination을 이 chat으로 (bridge가 sets requestChatId)
            await model.setBridgeRequestChatId(requestChatId)
            // ADR-045 R2.H5 — 외부 turn 카운터 증가
            await model.incrementExternalTurnCount()
            // ADR-046 — 외부 turn은 plan-mode 강제 (telegramRemoteRequiresPlan=true 시).
            // 1 turn 만 적용하고 자동 복원 — 사용자가 plan 검토 후 후속 turn으로 승인.
            let restoreSettings = await model.applyRemotePlanModeIfNeeded()
            await MainActor.run { model.inputText = text }
            // mention 우선 — `@codex` 같은 텍스트면 다른 pane으로 dispatch (ADR-031 T2)
            let dispatched = await model.tryDispatchMention()
            if !dispatched {
                await model.sendMessage()
            }
            // turn 종료 후 plan-mode 복원 (다음 turn은 다시 default)
            if let restore = restoreSettings {
                await model.scheduleSettingsRestore(restore)
            }
            // bridge가 응답 forwarding하므로 여기서는 nil
            return nil
        }
    }

    private enum Preflight {
        case notBound
        case boundMissing
        case ready(UUID, needsSwitch: Bool)
    }

    // MARK: - Help

    static let helpText = """
    Yuminai 텔레그램 명령:

    📌 연결 / 활성:
    /bind <이름>   — 이 chat을 워크스페이스에 연결 (응답 destination도 자동)
    /unbind       — 연결 해제
    /use <이름>    — 활성 워크스페이스만 변경 (bind 유지)
    /list         — 워크스페이스 목록 (✈ bound, ★ active)

    📊 상태 / 작업:
    /status       — 현재 상태 + 외부 turn 누적 비용
    /cancel       — 진행 중 turn + ChildProcess 모두 중단 (위험 작업 보면 즉시!)
    /diff         — 보류 중인 변경 diff (chunk 보존)
    /changes      — 변경 파일 목록만 요약
    /model <name> — 모델 전환 (claude/codex/auto/status)
    /decompose <설명> — 큰 task를 sub-task로 LLM 자동 분해 (격리 호출, 결과 자동 forward)
    /cost         — 5 buckets 비용 분리 (main/decomp/rehearsal/parallel/routing)
    /budget [USD] — per-turn cost cap 설정 (off로 해제)

    📋 Task 컨트롤 (ADR-056):
    /tasks         — TaskGraph 조회 (번호 포함)
    /walkthrough <번호> — 완료 task의 진행 회고 (text 응답)
    /rehearse <번호> <claude|codex> — 다른 모델로 리허설 launch

    /start        — 처음 사용자용 안내
    /help         — 이 도움말

    ⚠ 주의:
    • 외부 명령은 PC confirmation 없이 실행돼요
    • 위험한 작업 (rm -rf 등)은 🚨 알림 + /cancel 보낼 시간 있어요
    • 외부 turn은 PC와 같은 컨텍스트 — 비용 누적 (/status)
    """
}
