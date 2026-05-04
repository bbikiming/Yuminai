import Foundation
import Testing
@testable import YuminaiCore

/// **ADR-094 Phase 3** — TelegramCommand 모델 + Codable + Permission 테스트.
@Suite("TelegramCommand (ADR-094 Phase 3)")
struct TelegramCommandTests {

    // MARK: - Init + validation

    @Test("기본 init — enabled=true, requiresHITL=false")
    func defaultInit() {
        let cmd = TelegramCommand(trigger: "/run", description: "Execute in workspace")
        #expect(cmd.enabled == true)
        #expect(cmd.requiresHITL == false)
        #expect(cmd.permission == .anyUser)
    }

    @Test("trigger 유효성 — '/' prefix 필수")
    func triggerValidation() {
        let good = TelegramCommand(trigger: "/run", description: "desc")
        #expect(good.isValidTrigger == true)

        let bad = TelegramCommand(trigger: "run", description: "desc")
        #expect(bad.isValidTrigger == false)

        let empty = TelegramCommand(trigger: "/", description: "desc")
        #expect(empty.isValidTrigger == false)
    }

    @Test("trigger 유효성 — command 32자 초과 실패")
    func triggerMaxLength() {
        let long = TelegramCommand(trigger: "/" + String(repeating: "a", count: 33), description: "desc")
        #expect(long.isValidTrigger == false)

        let edge = TelegramCommand(trigger: "/" + String(repeating: "a", count: 32), description: "desc")
        #expect(edge.isValidTrigger == true)
    }

    @Test("description 유효성 — 1~256자")
    func descriptionValidation() {
        let empty = TelegramCommand(trigger: "/run", description: "")
        #expect(empty.isValidDescription == false)

        let ok = TelegramCommand(trigger: "/run", description: "Execute in workspace")
        #expect(ok.isValidDescription == true)

        let tooLong = TelegramCommand(trigger: "/run", description: String(repeating: "a", count: 257))
        #expect(tooLong.isValidDescription == false)

        let edge = TelegramCommand(trigger: "/run", description: String(repeating: "a", count: 256))
        #expect(edge.isValidDescription == true)
    }

    @Test("apiCommand — '/' prefix 제거")
    func apiCommandStrip() {
        let cmd = TelegramCommand(trigger: "/run", description: "desc")
        #expect(cmd.apiCommand == "run")

        let noPrefix = TelegramCommand(trigger: "status", description: "desc")
        #expect(noPrefix.apiCommand == "status")
    }

    // MARK: - Codable round-trip

    @Test("Codable round-trip — anyUser permission")
    func roundTripAnyUser() throws {
        let cmd = TelegramCommand(
            trigger: "/run",
            description: "Execute in workspace",
            permission: .anyUser,
            requiresHITL: false,
            enabled: true
        )
        let data = try JSONEncoder().encode(cmd)
        let decoded = try JSONDecoder().decode(TelegramCommand.self, from: data)
        #expect(decoded.id == cmd.id)
        #expect(decoded.trigger == "/run")
        #expect(decoded.permission == .anyUser)
        #expect(decoded.requiresHITL == false)
    }

    @Test("Codable round-trip — admin permission")
    func roundTripAdmin() throws {
        let cmd = TelegramCommand(trigger: "/switch", description: "Switch workspace", permission: .admin)
        let data = try JSONEncoder().encode(cmd)
        let decoded = try JSONDecoder().decode(TelegramCommand.self, from: data)
        #expect(decoded.permission == .admin)
    }

    @Test("Codable round-trip — userIds permission")
    func roundTripUserIds() throws {
        let ids: [Int64] = [111, 222, 333]
        let cmd = TelegramCommand(trigger: "/secret", description: "Secret cmd", permission: .userIds(ids))
        let data = try JSONEncoder().encode(cmd)
        let decoded = try JSONDecoder().decode(TelegramCommand.self, from: data)
        #expect(decoded.permission == .userIds(ids))
    }

    @Test("Codable round-trip — userIds empty list")
    func roundTripUserIdsEmpty() throws {
        let cmd = TelegramCommand(trigger: "/none", description: "No one", permission: .userIds([]))
        let data = try JSONEncoder().encode(cmd)
        let decoded = try JSONDecoder().decode(TelegramCommand.self, from: data)
        #expect(decoded.permission == .userIds([]))
    }

    @Test("Codable round-trip — requiresHITL=true")
    func roundTripHITL() throws {
        let cmd = TelegramCommand(trigger: "/deploy", description: "Deploy", requiresHITL: true)
        let data = try JSONEncoder().encode(cmd)
        let decoded = try JSONDecoder().decode(TelegramCommand.self, from: data)
        #expect(decoded.requiresHITL == true)
    }

    @Test("Codable round-trip — enabled=false")
    func roundTripDisabled() throws {
        let cmd = TelegramCommand(trigger: "/old", description: "Old cmd", enabled: false)
        let data = try JSONEncoder().encode(cmd)
        let decoded = try JSONDecoder().decode(TelegramCommand.self, from: data)
        #expect(decoded.enabled == false)
    }

    // MARK: - Default seeds

    @Test("defaultCommands — 7개")
    func defaultCommandCount() {
        #expect(TelegramCommand.defaultCommands.count == 7)
    }

    @Test("defaultCommands — 모두 '/' prefix")
    func defaultCommandsHaveSlash() {
        for cmd in TelegramCommand.defaultCommands {
            #expect(cmd.trigger.hasPrefix("/"), "'\(cmd.trigger)' should start with /")
        }
    }

    @Test("defaultCommands — /approve, /reject 포함")
    func defaultCommandsIncludeHITL() {
        let triggers = TelegramCommand.defaultCommands.map(\.trigger)
        #expect(triggers.contains("/approve"))
        #expect(triggers.contains("/reject"))
    }

    @Test("defaultCommands — 모두 isValidTrigger + isValidDescription")
    func defaultCommandsAllValid() {
        for cmd in TelegramCommand.defaultCommands {
            #expect(cmd.isValidTrigger, "'\(cmd.trigger)' trigger invalid")
            #expect(cmd.isValidDescription, "'\(cmd.trigger)' description invalid")
        }
    }

    // MARK: - Permission displayLabel

    @Test("Permission.displayLabel — anyUser")
    func displayLabelAnyUser() {
        #expect(TelegramCommand.Permission.anyUser.displayLabel == "전체")
    }

    @Test("Permission.displayLabel — admin")
    func displayLabelAdmin() {
        #expect(TelegramCommand.Permission.admin.displayLabel == "관리자")
    }

    @Test("Permission.displayLabel — userIds")
    func displayLabelUserIds() {
        #expect(TelegramCommand.Permission.userIds([1, 2]).displayLabel == "특정 2명")
        #expect(TelegramCommand.Permission.userIds([]).displayLabel == "없음")
    }

    // MARK: - Identifiable

    @Test("Identifiable — id는 UUID")
    func identifiable() {
        let cmd = TelegramCommand(trigger: "/run", description: "desc")
        #expect(cmd.id != UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
    }
}
