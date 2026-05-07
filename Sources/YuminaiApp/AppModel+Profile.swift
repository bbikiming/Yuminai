import Foundation
import AppKit
import os
import YuminaiCore
import YuminaiHarness

// ADR-127 — AppModel.swift 분할: Profile 도메인 (사용자 프로필 관리)
extension AppModel {

    // MARK: - ADR-106 — 사용자 프로필

    /// 프로필 갱신 + 모든 워크스페이스의 .harness/rules/USER_PROFILE.md + CLAUDE.md 자동 동기화.
    /// ADR-108: 3-pronged 주입 전략
    ///   1) system prompt — adapter의 userProfileProvider가 다음 spawn 시 자동 반영
    ///   2) .harness/rules/USER_PROFILE.md — 기존 방식 유지
    ///   3) <workspace>/CLAUDE.md marker 동기화 — Claude Code 자동 읽기
    public func updateUserProfile(_ profile: UserProfile) async {
        preferences.userProfile = profile
        await savePreferences()
        // 모든 워크스페이스에 프로필 파일 동기화
        for workspace in workspaces {
            let wsURL = URL(fileURLWithPath: workspace.directoryPath)
            await syncUserProfileTo(workspaceURL: wsURL)
            await syncUserProfileToCLAUDEMd(workspaceURL: wsURL)
        }
    }

    /// 프로필 이미지 선택 (NSOpenPanel). 선택된 파일을 앱 지원 디렉토리에 복사 후 경로 반환.
    @MainActor
    public func selectUserProfileImage() async -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "프로필 사진을 선택하세요"
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        do {
            let fm = FileManager.default
            let supportDir = try fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("Yuminai", isDirectory: true)
            try fm.createDirectory(at: supportDir, withIntermediateDirectories: true)
            let ext = url.pathExtension
            let destURL = supportDir.appendingPathComponent("profile-image.\(ext)")
            if fm.fileExists(atPath: destURL.path) {
                try fm.removeItem(at: destURL)
            }
            try fm.copyItem(at: url, to: destURL)
            return destURL.path
        } catch {
            self.error = "프로필 사진 복사 실패: \(error.localizedDescription)"
            return nil
        }
    }

    /// 단일 워크스페이스에 USER_PROFILE.md 작성/갱신.
    /// .harness 디렉토리가 없으면 skip (해당 워크스페이스는 하네스 미사용).
    func syncUserProfileTo(workspaceURL: URL) async {
        let layout = HarnessLayout(workspaceURL: workspaceURL)
        let fm = FileManager.default
        guard fm.fileExists(atPath: layout.harnessURL.path) else { return }
        let fileURL = layout.rulesURL.appendingPathComponent("USER_PROFILE.md")
        do {
            try fm.createDirectory(at: layout.rulesURL, withIntermediateDirectories: true)
            let content = preferences.userProfile.renderHarnessRules()
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            logger.error("USER_PROFILE.md 동기화 실패 (\(workspaceURL.lastPathComponent)): \(error.localizedDescription)")
        }
    }

    /// ADR-108 — 단일 워크스페이스의 CLAUDE.md에 Yuminai 프로필 섹션을 동기화.
    /// Claude Code는 <workspace>/CLAUDE.md를 자동으로 읽으므로 (Anthropic 공식),
    /// begin/end marker 사이만 갱신해 사용자 자체 내용은 보존한다.
    /// 워크스페이스 디렉토리가 없으면 skip.
    private func syncUserProfileToCLAUDEMd(workspaceURL: URL) async {
        let fm = FileManager.default
        guard fm.fileExists(atPath: workspaceURL.path) else { return }

        let mdURL = workspaceURL.appendingPathComponent("CLAUDE.md")
        let existing = try? String(contentsOf: mdURL, encoding: .utf8)

        let profileSection: String
        if preferences.userProfile.isEmpty {
            // 프로필 비어있으면 marker 블록 제거
            profileSection = ""
        } else {
            profileSection = preferences.userProfile.renderForCLAUDEMd()
        }

        let merged = CLAUDEMdMerger.merge(existing: existing, profileSection: profileSection)

        do {
            try merged.write(to: mdURL, atomically: true, encoding: .utf8)
        } catch {
            logger.error("CLAUDE.md 동기화 실패 (\(workspaceURL.lastPathComponent)): \(error.localizedDescription)")
        }
    }
}
