import Foundation
import Testing
import YuminaiCore
@testable import YuminaiTelegram

// ADR-153 — TelegramSessionBridge P1-3 + P1-4 bridge-level 회귀 테스트

private func makeConfig() -> TelegramSessionBridge.Configuration {
    TelegramSessionBridge.Configuration(
        chatId: 9999,
        workspaceName: "adr153-test",
        forwardAssistant: true,
        forwardToolCalls: true,
        maxChunkSize: 4096,
        flushInterval: .milliseconds(10)
    )
}

// MARK: - P1-3: CommandPolicyMatrix — deny 차단 흐름

@Suite("ADR-153 P1-3: CommandPolicyMatrix bridge 통합")
struct BridgeCommandPolicyTests {

    @Test("deny 정책 — rm -rf 차단 시 🚫 메시지 발송")
    func denyPolicyBlocksRmRf() async {
        let bot = MockTelegramBot()
        let bridge = TelegramSessionBridge(client: bot, configuration: makeConfig())
        // rm을 deny로 설정
        let matrix = CommandPolicyMatrix(
            allowList: [],
            allowPatterns: [],
            denyPatterns: ["^rm\\s"],
            autoApprovePermissions: false
        )
        await bridge.setCommandPolicyMatrix(matrix)

        let input = #"{"command":"rm -rf /tmp/build"}"#
        await bridge.consume(event: .toolCall(name: "Bash", input: input))

        let log = await bot.sentLog
        let hasBlock = log.contains { $0.text.contains("CommandPolicy 차단") || $0.text.contains("🚫") }
        #expect(hasBlock)
    }

    @Test("nil policy — CommandPolicy 검사 생략, 정상 tool 메시지 발송")
    func nilPolicySkipsCheck() async {
        let bot = MockTelegramBot()
        let bridge = TelegramSessionBridge(client: bot, configuration: makeConfig())
        await bridge.setCommandPolicyMatrix(nil)

        let input = #"{"command":"ls -la"}"#
        await bridge.consume(event: .toolCall(name: "Bash", input: input))

        let log = await bot.sentLog
        // 차단 메시지가 없어야 하고, 🔧 정상 메시지가 있어야 함
        #expect(!log.contains { $0.text.contains("CommandPolicy 차단") })
        #expect(log.contains { $0.text.contains("🔧") })
    }

    @Test("allow 정책인 명령은 차단 없이 정상 전달")
    func allowPolicyPassesThrough() async {
        let bot = MockTelegramBot()
        let bridge = TelegramSessionBridge(client: bot, configuration: makeConfig())
        let matrix = CommandPolicyMatrix(
            allowList: ["swift"],
            allowPatterns: [],
            denyPatterns: ["^sudo\\s"],
            autoApprovePermissions: false
        )
        await bridge.setCommandPolicyMatrix(matrix)

        let input = #"{"command":"swift build"}"#
        await bridge.consume(event: .toolCall(name: "Bash", input: input))

        let log = await bot.sentLog
        #expect(!log.contains { $0.text.contains("CommandPolicy 차단") })
        #expect(log.contains { $0.text.contains("🔧") })
    }
}

// MARK: - P1-4: isDestructiveToolCall — HITLActionGuard 위임

@Suite("ADR-153 P1-4: isDestructiveToolCall HITLActionGuard 위임")
struct BridgeDestructiveTests {

    @Test("rm -rf Bash tool — isDestructiveToolCall true")
    func rmRfIsDestructive() {
        let input = #"{"command":"rm -rf /tmp"}"#
        #expect(TelegramSessionBridge.isDestructiveToolCall(name: "Bash", input: input))
    }

    @Test("swift build Bash tool — isDestructiveToolCall false")
    func swiftBuildNotDestructive() {
        let input = #"{"command":"swift build"}"#
        #expect(!TelegramSessionBridge.isDestructiveToolCall(name: "Bash", input: input))
    }

    @Test("Read tool — isDestructiveToolCall false (비-Bash)")
    func readToolNotDestructive() {
        let input = #"{"path":"/etc/hosts"}"#
        #expect(!TelegramSessionBridge.isDestructiveToolCall(name: "Read", input: input))
    }

    @Test("HITLActionGuard 결과와 bridge 결과 일치")
    func bridgeMatchesGuard() {
        let cmds = [
            "rm -rf /tmp",
            "sudo rm -rf /",
            "chmod -R 777 /etc",
            "ls -la",
            "swift test",
            "git diff"
        ]
        for cmd in cmds {
            let input = #"{"command":"\#(cmd)"}"#
            let bridge = TelegramSessionBridge.isDestructiveToolCall(name: "Bash", input: input)
            let guard_ = HITLActionGuard.shouldRequestApproval(command: cmd)
            #expect(bridge == guard_, "'\(cmd)': bridge=\(bridge), guard=\(guard_)")
        }
    }
}
