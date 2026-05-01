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
        guard let raw = message.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else {
            return nil
        }

        if raw.hasPrefix("/") {
            return await handleCommand(raw)
        }
        return await handlePlainText(raw)
    }

    // MARK: - Commands

    private func handleCommand(_ text: String) async -> String? {
        let split = text.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let cmd = split[0].lowercased()
        let arg = split.count > 1
            ? String(split[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""

        switch cmd {
        case "/bind":
            return await bindCommand(arg)
        case "/unbind":
            return await unbindCommand()
        case "/status":
            return await statusCommand()
        case "/cancel", "/stop":
            return await cancelCommand()
        case "/help", "/start":
            return Self.helpText
        case "/list", "/workspaces":
            return await listWorkspaces()
        default:
            return "알 수 없는 명령: \(cmd)\n/help로 사용 가능한 명령을 확인해요."
        }
    }

    private func bindCommand(_ name: String) async -> String? {
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

        await model.bindTelegramWorkspace(workspace.id)
        return "✓ ‘\(workspace.name)’에 연결됐어요. 이제 텍스트를 보내면 이 세션의 Claude로 전달돼요."
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
            return model.workspaces.map { ws in
                ws.id == bound ? "✈ \(ws.name)" : "  \(ws.name)"
            }
        }
        if names.isEmpty {
            return "아직 워크스페이스가 없어요. Yuminai에서 만든 후 다시 시도해주세요."
        }
        return "워크스페이스 목록:\n" + names.joined(separator: "\n") + "\n\n✈ = 현재 텔레그램 연결됨"
    }

    // MARK: - Plain text → bound session

    private func handlePlainText(_ text: String) async -> String? {
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
            await MainActor.run { model.inputText = text }
            await model.sendMessage()
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

    /bind <이름>  — 워크스페이스를 이 챗에 연결
    /unbind      — 연결 해제
    /status      — 현재 상태
    /cancel      — 진행 중 turn 중단
    /list        — 워크스페이스 목록 (✈ = bound)
    /help        — 이 도움말

    연결 후 일반 텍스트를 보내면 bound 세션의 Claude에 전달돼요.
    Claude의 응답은 자동으로 텔레그램에 forwarding됩니다.
    """
}
