import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-094 Phase 3** — Telegram Hub Commands 탭.
///
/// `CommandPaletteEditor`를 호스팅. BotFather 커맨드 등록 및 HITL 설정.
struct TelegramHubCommandsTab: View {
    var body: some View {
        CommandPaletteEditor()
    }
}
