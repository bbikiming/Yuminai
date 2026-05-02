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
        await model.bindTelegramWorkspace(workspace.id, defaultChatId: requestChatId)
        return "✓ ‘\(workspace.name)’에 연결됐어요. 이제 이 chat에서 텍스트를 보내면 Claude로 전달되고, 응답도 이 chat으로 와요."
    }

    private func unbindCommand() async -> String? {
        guard let model = appModel else { return "Yuminai 연결 안 됨" }
        let prevName = await MainActor.run { model.boundWorkspaceName }
        await model.bindTelegramWorkspace(nil)
        if let prevName {
            return "✓ ‘\(prevName)’ 연결 해제. 이제 일반 텍스트는 무시돼요."
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
            guard let boundId = model.preferences.telegramBoundWorkspaceId else {
                return .notBound
            }
            guard model.workspaces.contains(where: { $0.id == boundId }) else {
                return .boundMissing
            }
            return .ready(boundId, needsSwitch: model.selectedWorkspaceId != boundId)
        }

        switch preflight {
        case .notBound:
            return "먼저 /bind <워크스페이스 이름>으로 세션을 연결해주세요. /list로 목록 확인."
        case .boundMissing:
            return "연결된 워크스페이스를 찾을 수 없어요. /unbind 후 다시 /bind 해주세요."
        case .ready(let boundId, let needsSwitch):
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
    /cancel       — 진행 중 turn 중단 (위험 작업 보면 즉시!)
    /diff         — 보류 중인 변경 diff (chunk 보존)
    /changes      — 변경 파일 목록만 요약
    /model <name> — 모델 전환 (claude/codex/auto/status)

    /start        — 처음 사용자용 안내
    /help         — 이 도움말

    ⚠ 주의:
    • 외부 명령은 PC confirmation 없이 실행돼요
    • 위험한 작업 (rm -rf 등)은 🚨 알림 + /cancel 보낼 시간 있어요
    • 외부 turn은 PC와 같은 컨텍스트 — 비용 누적 (/status)
    """
}
