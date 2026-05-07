import Foundation
import AppKit
import os
import YuminaiCore
import YuminaiTelegram

// ADR-127 — AppModel.swift 분할: DeepLink 도메인 (yuminai:// deep link 라우팅)
extension AppModel {

    // MARK: - ADR-096 — Deep link 핸들러

    /// **ADR-096** — `yuminai://` deep link 수신 시 라우팅.
    ///
    /// `.onOpenURL` 핸들러에서 호출 — `TelegramDeepLink.parse(url)` 결과를 액션에 매핑.
    public func handleDeepLink(_ link: TelegramDeepLink) async {
        switch link {
        case .diff(let id):
            // ADR-097 — artifact viewer sheet로 라우팅
            NSApp.activate(ignoringOtherApps: true)
            artifactSheetId = id
            showTelegramArtifactSheet = true
            logger.info("[DeepLink] diff \(id) — artifact viewer sheet 표시")

        case .log(let id):
            // ADR-097 — artifact viewer sheet로 라우팅
            NSApp.activate(ignoringOtherApps: true)
            artifactSheetId = id
            showTelegramArtifactSheet = true
            logger.info("[DeepLink] log \(id) — artifact viewer sheet 표시")

        case .workspace(let id):
            NSApp.activate(ignoringOtherApps: true)
            await transitionToWorkspace(id)

        case .chat:
            NSApp.activate(ignoringOtherApps: true)
            showTelegramHubSheet = true

        case .approve(let requestId):
            await respondToHITL(id: requestId, response: .approved(by: "deeplink"))

        case .reject(let requestId):
            await respondToHITL(id: requestId, response: .rejected(by: "deeplink"))
        }
    }
}
