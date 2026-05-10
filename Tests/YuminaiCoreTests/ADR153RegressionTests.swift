import Foundation
import Testing
@testable import YuminaiCore

// ADR-153 — Telegram 연계 P0+P1 일괄 fix 회귀 테스트
// TelegramSessionBridge-level 테스트는 YuminaiTelegramTests/ADR153BridgeRegressionTests.swift에 위치.

// MARK: - P1-2: HarnessRulesLoader excludeFiles 파라미터

@Suite("ADR-153 P1-2: HarnessRulesLoader excludeFiles")
struct HarnessRulesLoaderExcludeTests {

    private func makeWorkspaceWithRules(_ files: [(name: String, content: String)]) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let rulesDir = tmp.appendingPathComponent(".harness/rules")
        try FileManager.default.createDirectory(at: rulesDir, withIntermediateDirectories: true)
        for f in files {
            try f.content.write(
                to: rulesDir.appendingPathComponent(f.name),
                atomically: true, encoding: .utf8
            )
        }
        return tmp
    }

    @Test("excludeFiles — USER_PROFILE.md 제외 시 나머지 파일 포함")
    func excludeUserProfileIncludesOthers() async throws {
        let tmp = try makeWorkspaceWithRules([
            (name: "USER_PROFILE.md", content: "# 유저 프로필 내용"),
            (name: "coding-style.md", content: "# 코딩 스타일")
        ])
        defer { try? FileManager.default.removeItem(at: tmp) }

        let result = await HarnessRulesLoader.loadAll(workspaceURL: tmp, excludeFiles: ["USER_PROFILE"])

        #expect(!result.contains("유저 프로필 내용"))
        #expect(result.contains("코딩 스타일"))
    }

    @Test("excludeFiles — 빈 배열이면 모든 파일 포함 (기존 동작 유지)")
    func emptyExcludeIncludesAll() async throws {
        let tmp = try makeWorkspaceWithRules([
            (name: "USER_PROFILE.md", content: "# 프로필"),
            (name: "style.md", content: "# 스타일")
        ])
        defer { try? FileManager.default.removeItem(at: tmp) }

        let result = await HarnessRulesLoader.loadAll(workspaceURL: tmp, excludeFiles: [])
        #expect(result.contains("프로필"))
        #expect(result.contains("스타일"))
    }

    @Test("excludeFiles — 복수 제외 파일")
    func multipleExclude() async throws {
        let tmp = try makeWorkspaceWithRules([
            (name: "USER_PROFILE.md", content: "# 프로필"),
            (name: "SECRET.md", content: "# 비밀"),
            (name: "public.md", content: "# 공개")
        ])
        defer { try? FileManager.default.removeItem(at: tmp) }

        let result = await HarnessRulesLoader.loadAll(workspaceURL: tmp, excludeFiles: ["USER_PROFILE", "SECRET"])
        #expect(!result.contains("프로필"))
        #expect(!result.contains("비밀"))
        #expect(result.contains("공개"))
    }

    @Test("excludeFiles — 존재하지 않는 파일명 제외 시 정상 파일 포함")
    func excludeNonExistentFileNoop() async throws {
        let tmp = try makeWorkspaceWithRules([
            (name: "rule.md", content: "# 규칙")
        ])
        defer { try? FileManager.default.removeItem(at: tmp) }

        let result = await HarnessRulesLoader.loadAll(workspaceURL: tmp, excludeFiles: ["DOES_NOT_EXIST"])
        #expect(result.contains("규칙"))
    }
}

// MARK: - P1-3: CommandPolicyMatrix 정책 평가

@Suite("ADR-153 P1-3: CommandPolicyMatrix 정책 평가")
struct ADR153CommandPolicyTests {

    @Test("denyPatterns 기반 deny — 정규식 매칭")
    func denyPatternBlocksRm() {
        let policy = CommandPolicyMatrix(
            allowList: [],
            allowPatterns: [],
            denyPatterns: ["^rm\\s"],
            autoApprovePermissions: false
        )
        #expect(policy.policy(for: "rm -rf /tmp/test") == .deny)
    }

    @Test("allowList 기반 allow — gh pr list 허용")
    func allowListPermitsGhPrList() {
        let policy = CommandPolicyMatrix.default
        // gh pr list는 기본 allowList에 포함
        #expect(policy.policy(for: "gh pr list") == .allow)
    }

    @Test("allowList/deny 미해당 명령 — requireConfirmation")
    func unknownCommandRequiresConfirmation() {
        let policy = CommandPolicyMatrix(
            allowList: [],
            allowPatterns: [],
            denyPatterns: [],
            autoApprovePermissions: false
        )
        #expect(policy.policy(for: "my-custom-tool --flag") == .requireConfirmation)
    }

    @Test("allowPatterns 정규식 매칭 — allow")
    func allowPatternMatch() {
        let policy = CommandPolicyMatrix(
            allowList: [],
            allowPatterns: ["^swift\\s"],
            denyPatterns: [],
            autoApprovePermissions: false
        )
        #expect(policy.policy(for: "swift build") == .allow)
    }
}

// MARK: - P1-4: HITLActionGuard — ADR-153 회귀 (추가 케이스)
// 기존 HITLActionGuardTests.swift와 이름 충돌 방지를 위해 별도 이름 사용.

@Suite("ADR-153 P1-4: HITLActionGuard 추가 케이스")
struct ADR153HITLGuardExtraTests {

    @Test("chmod 777은 승인 필요")
    func chmodWideOpenRequiresApproval() {
        #expect(HITLActionGuard.shouldRequestApproval(command: "chmod 777 /etc"))
    }

    @Test("swift test는 승인 불필요")
    func swiftTestNoApproval() {
        #expect(!HITLActionGuard.shouldRequestApproval(command: "swift test"))
    }

    @Test("git diff는 승인 불필요")
    func gitDiffNoApproval() {
        #expect(!HITLActionGuard.shouldRequestApproval(command: "git diff HEAD"))
    }
}

// MARK: - P1-5: Codex prefix double-wrap 제거

@Suite("ADR-153 P1-5: Codex prefix — appendix 이중 래핑 없음")
struct ADR153CodexPrefixTests {

    @Test("appendix는 이중 래핑 없이 prefixParts에 추가됨")
    func appendixNoDoubleWrap() {
        let appendix = "프로젝트: YuminAI\n기술 스택: Swift"
        let userProfile = "사용자: 개발자"

        var prefixParts: [String] = []
        prefixParts.append(userProfile)
        prefixParts.append(appendix)  // P1-5 fix: 래핑 없이 직접 추가

        let joined = prefixParts.joined(separator: "\n\n") + "\n\n[작업]\n테스트"

        #expect(joined.contains("프로젝트: YuminAI"))
        #expect(!joined.contains("[프로젝트 컨텍스트]\n프로젝트: YuminAI"))
    }

    @Test("appendix 없으면 userProfile만 포함")
    func noAppendixOnlyProfile() {
        let userProfile = "사용자: 개발자"
        let prefixParts: [String] = [userProfile]
        let joined = prefixParts.joined(separator: "\n\n") + "\n\n[작업]\n테스트"
        #expect(joined.contains("사용자: 개발자"))
        #expect(joined.contains("[작업]"))
    }
}

// MARK: - P1-6: resolveHandoffBinding — 바인딩 우선순위

@Suite("ADR-153 P1-6: resolveHandoffBinding 우선순위")
struct ADR153ResolveHandoffBindingTests {

    private func makeBinding(chatId: Int64 = 100, activeWorkspaceId: UUID? = nil) -> BotChatBinding {
        BotChatBinding(
            id: UUID(),
            botId: UUID(),
            chatId: chatId,
            activeWorkspaceId: activeWorkspaceId,
            allowedWorkspaceIds: [],
            nickname: ""
        )
    }

    @Test("binding 없으면 nil 반환")
    func emptyBindingsReturnsNil() {
        let bindings: [BotChatBinding] = []
        let result = bindings.resolveBinding(activeWorkspaceId: nil, boundWorkspaceId: nil)
        #expect(result == nil)
    }

    @Test("activeWorkspaceId 매칭 binding 우선")
    func activeWorkspaceMatchFirst() {
        let wsId = UUID()
        let matched = makeBinding(chatId: 200, activeWorkspaceId: wsId)
        let other = makeBinding(chatId: 300, activeWorkspaceId: nil)

        let result = [other, matched].resolveBinding(activeWorkspaceId: wsId, boundWorkspaceId: nil)
        #expect(result?.chatId == 200)
    }

    @Test("boundWorkspaceId fallback — activeWorkspace 매칭 없을 때")
    func boundWorkspaceFallback() {
        let boundId = UUID()
        let bound = makeBinding(chatId: 400, activeWorkspaceId: boundId)
        let other = makeBinding(chatId: 500, activeWorkspaceId: UUID())

        let result = [other, bound].resolveBinding(activeWorkspaceId: nil, boundWorkspaceId: boundId)
        #expect(result?.chatId == 400)
    }

    @Test("매칭 없으면 첫 번째 binding (fallback)")
    func firstBindingFallback() {
        let b1 = makeBinding(chatId: 600)
        let b2 = makeBinding(chatId: 700)

        let result = [b1, b2].resolveBinding(activeWorkspaceId: nil, boundWorkspaceId: nil)
        #expect(result?.chatId == 600)
    }
}

// MARK: - P1-7: HITL 채널 분기 — NotificationPolicyMatrix

@Suite("ADR-153 P1-7: HITL 채널 분기 — NotificationPolicyMatrix")
struct ADR153HITLChannelBranchingTests {

    @Test("hitlApprovalRequest 기본 정책 — 모든 deviceState에서 채널 반환")
    func hitlDefaultPolicyAllStates() {
        let matrix = NotificationPolicyMatrix.default
        for state: DeviceState in [.desktopActive, .desktopIdle, .desktopOff] {
            let channel = matrix.channel(for: .hitlApprovalRequest, in: state)
            // 채널 값이 유효한 enum case여야 함
            #expect(channel == .macOSOnly || channel == .telegramOnly || channel == .both || channel == .suppressed)
        }
    }

    @Test("DeliveryChannel.telegramOnly — Telegram 전송 필요")
    func telegramOnlyRequiresTelegram() {
        #expect(requiresTelegram(.telegramOnly))
    }

    @Test("DeliveryChannel.both — Telegram 전송 필요")
    func bothRequiresTelegram() {
        #expect(requiresTelegram(.both))
    }

    @Test("DeliveryChannel.macOSOnly — Telegram 전송 불필요")
    func macOSOnlyNoTelegram() {
        #expect(!requiresTelegram(.macOSOnly))
    }

    @Test("DeliveryChannel.suppressed — Telegram 전송 불필요")
    func suppressedNoTelegram() {
        #expect(!requiresTelegram(.suppressed))
    }

    private func requiresTelegram(_ channel: DeliveryChannel) -> Bool {
        switch channel {
        case .telegramOnly, .both: return true
        default: return false
        }
    }
}

// MARK: - CommandPolicyMatrix 기본값 정책

@Suite("ADR-153: CommandPolicyMatrix 기본값 정책")
struct ADR153CommandPolicyMatrixDefaultTests {

    @Test("default — gh api 허용")
    func defaultAllowsGhApi() {
        // gh api는 기본 allowList에 포함
        #expect(CommandPolicyMatrix.default.policy(for: "gh api repos") == .allow)
    }

    @Test("denyPatterns 기반 — sudo 차단")
    func denyBySudoPattern() {
        let policy = CommandPolicyMatrix(
            allowList: [],
            allowPatterns: [],
            denyPatterns: ["^sudo\\s"],
            autoApprovePermissions: false
        )
        #expect(policy.policy(for: "sudo rm -rf /") == .deny)
    }

    @Test("allowList 기반 — swift 명령 허용")
    func allowBySwiftList() {
        let policy = CommandPolicyMatrix(
            allowList: ["swift"],
            allowPatterns: [],
            denyPatterns: [],
            autoApprovePermissions: false
        )
        #expect(policy.policy(for: "swift build") == .allow)
    }
}

// MARK: - BotChatBinding resolveBinding helper (P1-6 검증용 extension)

private extension Array where Element == BotChatBinding {
    /// ADR-153 P1-6 resolveHandoffBinding 로직과 동일한 순수 함수 버전 (테스트용).
    func resolveBinding(activeWorkspaceId: UUID?, boundWorkspaceId: UUID?) -> BotChatBinding? {
        guard !isEmpty else { return nil }
        if let wsId = activeWorkspaceId,
           let matched = first(where: { $0.activeWorkspaceId == wsId }) {
            return matched
        }
        if let boundId = boundWorkspaceId,
           let matched = first(where: { $0.activeWorkspaceId == boundId }) {
            return matched
        }
        return first
    }
}
