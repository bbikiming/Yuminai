import Foundation
import YuminaiCore
import YuminaiTelegram

/// Telegram에서 받은 메시지를 Yuminai 워크스페이스 채팅에 전달하는 라우터.
///
/// MVP는 가장 단순한 정책: 메시지 본문을 현재 활성 워크스페이스의 채팅 입력에 넣고 전송.
/// 더 정교한 명령 체계 (`#workspace command` 등)는 v0.3에서 확장.
public final class YuminaiCommandRouter: TelegramCommandRouter, @unchecked Sendable {
    weak var appModel: AppModel?

    public init(appModel: AppModel) {
        self.appModel = appModel
    }

    public func handle(_ message: IncomingTelegramMessage) async -> String? {
        guard let text = message.text,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        let appModelRef = self.appModel
        await MainActor.run {
            guard let model = appModelRef else { return }
            guard model.selectedWorkspaceId != nil else { return }
            model.inputText = text
        }
        await appModelRef?.sendMessage()

        let preview = String(text.prefix(60))
        return "[YUMINAI] 명령 수신: \(preview)"
    }
}
