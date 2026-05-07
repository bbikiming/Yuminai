import Foundation
import AppKit
import YuminaiCore

// ADR-127 — AppModel.swift 분할: Setup 도메인 (Setup Wizard + Binary Picker)
extension AppModel {

    // MARK: - Binary picker (Claude / Codex CLI 경로 선택)

    /// Claude CLI 실행 파일 경로를 NSOpenPanel로 선택해 preferences에 저장.
    public func selectClaudeBinary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Claude CLI 실행 파일을 선택하세요"
        if panel.runModal() == .OK, let url = panel.url {
            preferences.claudeBinaryPath = url.path
            Task { await savePreferences() }
        }
    }

    /// Codex CLI 실행 파일 경로를 NSOpenPanel로 선택해 preferences에 저장.
    public func selectCodexBinary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Codex CLI 실행 파일을 선택하세요"
        if panel.runModal() == .OK, let url = panel.url {
            preferences.codexBinaryPath = url.path
            Task { await savePreferences() }
        }
    }

    // MARK: - ADR-104 — Setup Wizard

    /// 모든 도구의 설치 상태를 재검사하고 `setupToolStatus`를 갱신.
    public func refreshSetupStatus() async {
        let result = await setupChecker.checkAll()
        setupToolStatus = result
    }

    /// Setup wizard를 명시적으로 열기 (Help 메뉴 등에서 사용).
    public func openSetupWizard() {
        Task { await refreshSetupStatus() }
        presentExclusiveSheet { $0.showSetupWizard = true }
    }

    /// Setup wizard 닫기.
    /// - Parameter markCompleted: true이면 `hasCompletedSetup = true`로 저장. false이면 다음 실행 시 다시 표시.
    ///
    /// **ADR-115 P1-3** — 완료 시 프로필이 비어 있으면 300ms 후 프로필 sheet를 자동으로 표시한다.
    /// 애니메이션 완료 후 열어야 자연스럽게 나타난다.
    public func dismissSetupWizard(markCompleted: Bool) {
        showSetupWizard = false
        if markCompleted {
            preferences.hasCompletedSetup = true
            Task { await savePreferences() }
            // ADR-115 P1-3 — 프로필 미입력이면 setup 닫힘 후 프로필 sheet 자동 유도
            if preferences.userProfile.isEmpty {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000)  // 0.3s — sheet 닫힘 애니메이션 대기
                    self.showUserProfileSheet = true
                }
            }
        }
    }
}
