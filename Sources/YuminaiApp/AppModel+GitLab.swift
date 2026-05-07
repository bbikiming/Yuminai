import Foundation
import os
import YuminaiCore
import YuminaiClaudeAdapter
import YuminaiPersistence
import YuminaiTelegram
import YuminaiHarness

/// **ADR-133** — AppModel GitLab 도메인 (PAT + 명령 정책 평가).
extension AppModel {

    // MARK: - ADR-133 — GitLab PAT

    /// GitLab PAT를 Keychain에 저장하고 preferences 메타를 갱신한다.
    public func saveGitLabPAT(_ token: String) async throws {
        try await keychainStore.set(token, for: KeychainKey.gitlabPersonalAccessToken)
        gitlabPATStatus = .set
        preferences.hasGitLabPAT = true
        await savePreferences()
    }

    /// GitLab PAT를 Keychain에서 삭제하고 preferences 메타를 초기화한다.
    public func removeGitLabPAT() async {
        try? await keychainStore.remove(KeychainKey.gitlabPersonalAccessToken)
        gitlabPATStatus = .notSet
        preferences.hasGitLabPAT = false
        await savePreferences()
    }

    /// Keychain에서 GitLab PAT를 읽어 반환한다. 없으면 nil.
    public func loadGitLabPAT() async -> String? {
        try? await keychainStore.get(KeychainKey.gitlabPersonalAccessToken)
    }

    // MARK: - ADR-133 — 명령 정책 평가

    /// `command`에 대한 실행 정책을 현재 preferences의 CommandPolicyMatrix로 평가한다.
    ///
    /// AutoRun + 일반 명령 실행 경로 모두에서 이 메서드를 사용해야 한다.
    ///
    /// ## 평가 순서 (CommandPolicyMatrix.policy 참조)
    /// 1. denyPatterns → `.deny`
    /// 2. allowList 정확 prefix 매칭 → `.allow`
    /// 3. allowPatterns 정규식 → `.allow`
    /// 4. 기본 → `.requireConfirmation`
    public func evaluateCommand(_ command: String) -> CommandPolicy {
        preferences.commandPolicy.policy(for: command)
    }

    /// 현재 자동 승인 정책 요약 (UI 표시용).
    ///
    /// 예: "자동 승인 12개 · 차단 18개 · 나머지 확인 필요"
    public func commandPolicySummary() -> String {
        let policy = preferences.commandPolicy
        let allowCount = policy.allowList.count + policy.allowPatterns.count
        let denyCount = policy.denyPatterns.count
        return "자동 승인 \(allowCount)개 · 차단 \(denyCount)개 · 나머지 확인 필요"
    }

    // MARK: - 내부 — 시작 시 GitLab PAT 상태 로드

    /// 앱 시작 시 GitLab PAT 상태를 Keychain에서 확인한다.
    /// `loadSecrets()`와 유사한 패턴.
    func loadGitLabPATStatus() async {
        let token = await loadGitLabPAT()
        gitlabPATStatus = token != nil ? .set : .notSet
        // preferences 메타와 동기화
        if preferences.hasGitLabPAT != (token != nil) {
            preferences.hasGitLabPAT = (token != nil)
            await savePreferences()
        }
    }
}
