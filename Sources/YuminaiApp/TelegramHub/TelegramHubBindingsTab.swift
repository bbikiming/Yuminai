import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-092 Phase 1** — Telegram Hub Bindings 탭.
///
/// `TelegramBotBindingSection`을 재사용하는 단순 wrapper.
/// Chat ↔ Workspace 매핑 관리.
struct TelegramHubBindingsTab: View {
    var body: some View {
        TelegramBotBindingSection()
    }
}
