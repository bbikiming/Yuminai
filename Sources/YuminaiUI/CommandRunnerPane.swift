import SwiftUI
import YuminaiCore

/// Warp-style command block pane (ADR-036 C4 단순화).
///
/// SwiftTerm은 line-based PTY emulator라 block grouping 불가 → 별개 패널로 단순화:
/// - 사용자가 TextField에 명령 입력 → Run 클릭 (또는 ⌘Return)
/// - NSTask로 1회 실행 + 결과를 block으로 누적
/// - 각 block: 명령 / exit code / 시간 / collapse 가능
///
/// 진짜 zsh interactive 환경은 SwiftTerm 패널(⌘⌥T) 사용. 이 pane은 "기록되는 명령" 용도.
public struct CommandRunnerPane: View {
    public let workingDirectory: String
    public let blocks: [CommandRunner.CommandResult]
    public let isRunning: Bool
    public let quickCommands: [QuickCommand]
    public let onRun: (String) -> Void
    public let onClear: () -> Void
    public let onClose: () -> Void
    public let onCopyOutput: (String) -> Void
    public let onShareToAgent: (CommandRunner.CommandResult) -> Void

    @State private var draft: String = ""

    public init(
        workingDirectory: String,
        blocks: [CommandRunner.CommandResult],
        isRunning: Bool,
        quickCommands: [QuickCommand] = [],
        onRun: @escaping (String) -> Void,
        onClear: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onCopyOutput: @escaping (String) -> Void = { _ in },
        onShareToAgent: @escaping (CommandRunner.CommandResult) -> Void = { _ in }
    ) {
        self.workingDirectory = workingDirectory
        self.blocks = blocks
        self.isRunning = isRunning
        self.quickCommands = quickCommands
        self.onRun = onRun
        self.onClear = onClear
        self.onClose = onClose
        self.onCopyOutput = onCopyOutput
        self.onShareToAgent = onShareToAgent
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            if !quickCommands.isEmpty {
                quickCommandRow
            }
            FlatHDivider()
            blockList
            FlatHDivider()
            inputBar
        }
        .background(Theme.Color.bg)
    }

    @ViewBuilder
    private var quickCommandRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Text("Quick:")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                ForEach(quickCommands) { qc in
                    QuickCommandChip(quick: qc) { onRun(qc.command) }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 4)
        }
        .background(Theme.Color.surface.opacity(0.4))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.Color.accent)
            Text("Commands")
                .font(Theme.Typography.small.weight(.medium))
                .foregroundStyle(Theme.Color.text)
            Text(URL(fileURLWithPath: workingDirectory).lastPathComponent)
                .font(Theme.Typography.monoSmall)
                .foregroundStyle(Theme.Color.textTertiary)
            HelpHint(
                "한 번에 한 명령 실행 + 결과를 block으로 기록합니다. Warp-style 인터페이스. ⌘⌥T 터미널은 interactive zsh, 이건 ‘기록되는 명령’ 용도예요. 각 block은 collapse 가능, 출력 텍스트 select/copy 가능.",
                title: "Command Runner",
                placement: .bottom
            )
            if isRunning {
                ProgressView().controlSize(.mini).padding(.leading, 4)
            }
            Spacer()
            if !blocks.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                .buttonStyle(.plain)
                .help("기록 비우기")
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Command Runner 닫기")
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Color.surface)
    }

    @ViewBuilder
    private var blockList: some View {
        if blocks.isEmpty {
            EmptyStateHint(
                icon: "terminal",
                title: "아직 실행한 명령이 없어요",
                message: "아래 입력창에 명령을 입력하고 ⌘Return으로 실행하세요. 결과가 block으로 기록됩니다."
            )
            .frame(maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(blocks) { block in
                            CommandBlockView(
                                block: block,
                                onRerun: onRun,
                                onCopyOutput: onCopyOutput,
                                onShareToAgent: onShareToAgent
                            )
                            .id(block.id)
                        }
                    }
                    .padding(Theme.Spacing.sm)
                }
                .onChange(of: blocks.last?.id) { _, _ in
                    if let last = blocks.last {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 6) {
            Text("$")
                .font(Theme.Typography.mono)
                .foregroundStyle(Theme.Color.accent)
            TextField("명령 입력 (예: swift test, git status)", text: $draft)
                .textFieldStyle(.plain)
                .font(Theme.Typography.mono)
                .onSubmit { runDraft() }
            Button(action: runDraft) {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                    Text("실행")
                        .font(Theme.Typography.small)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(canRun ? Theme.Color.accent : Theme.Color.surfaceHi)
                .foregroundStyle(canRun ? .white : Theme.Color.textTertiary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .disabled(!canRun)
            .keyboardShortcut(.return, modifiers: .command)
            .help("⌘Return — 명령 실행")
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Color.surface)
    }

    private var canRun: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isRunning
    }

    private func runDraft() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onRun(trimmed)
        draft = ""
    }
}

/// Quick command 정의 (ADR-037 D6).
public struct QuickCommand: Sendable, Identifiable, Hashable {
    public let id: String
    public let label: String
    public let command: String
    public let icon: String

    public init(label: String, command: String, icon: String = "terminal") {
        self.id = command
        self.label = label
        self.command = command
        self.icon = icon
    }

    /// workspace의 deliveryConfig + 일반적 명령들 + 사용자 정의 (ADR-038 E4).
    public static func defaults(
        test: String?,
        build: String?,
        lint: String?,
        custom: [CustomQuickCommand] = []
    ) -> [QuickCommand] {
        var result: [QuickCommand] = []
        if let test, !test.isEmpty {
            result.append(.init(label: "테스트", command: test, icon: "checkmark.shield"))
        }
        if let build, !build.isEmpty {
            result.append(.init(label: "빌드", command: build, icon: "hammer"))
        }
        if let lint, !lint.isEmpty {
            result.append(.init(label: "린트", command: lint, icon: "magnifyingglass"))
        }
        // 사용자 정의 (앞쪽에) — 빈 command는 skip (sheet sanitize 보조 방어)
        for custom in custom where !custom.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let displayLabel = custom.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? custom.command
                : custom.label
            result.append(.init(label: displayLabel, command: custom.command, icon: "sparkles"))
        }
        // 일반적인 git 명령
        result.append(contentsOf: [
            .init(label: "git status", command: "git status", icon: "arrow.triangle.branch"),
            .init(label: "git diff", command: "git diff", icon: "doc.plaintext"),
            .init(label: "git log -5", command: "git log -5 --oneline", icon: "list.bullet")
        ])
        return result
    }
}

private struct QuickCommandChip: View {
    let quick: QuickCommand
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 3) {
                Image(systemName: quick.icon)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.Color.accent)
                Text(quick.label)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.text)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(hovering ? Theme.Color.surfaceHi : Theme.Color.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Theme.Color.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("실행: \(quick.command)")
    }
}

private struct CommandBlockView: View {
    let block: CommandRunner.CommandResult
    let onRerun: (String) -> Void
    let onCopyOutput: (String) -> Void
    let onShareToAgent: (CommandRunner.CommandResult) -> Void
    @State private var collapsed: Bool = false
    @State private var hovering: Bool = false

    init(
        block: CommandRunner.CommandResult,
        onRerun: @escaping (String) -> Void = { _ in },
        onCopyOutput: @escaping (String) -> Void = { _ in },
        onShareToAgent: @escaping (CommandRunner.CommandResult) -> Void = { _ in }
    ) {
        self.block = block
        self.onRerun = onRerun
        self.onCopyOutput = onCopyOutput
        self.onShareToAgent = onShareToAgent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !collapsed {
                if !block.stdout.isEmpty {
                    outputView(block.stdout, isStderr: false)
                }
                if !block.stderr.isEmpty {
                    outputView(block.stderr, isStderr: true)
                }
            }
        }
        .background(Theme.Color.surface.opacity(0.7))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .stroke(block.success ? Theme.Color.borderSubtle : SwiftUI.Color.red.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .onHover { hovering = $0 }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.10)) { collapsed.toggle() }
            } label: {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .buttonStyle(.plain)
            Image(systemName: block.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(block.success ? .green : .red)
            Text("$ \(block.command)")
                .font(Theme.Typography.mono)
                .foregroundStyle(Theme.Color.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer()
            if hovering {
                Button { onCopyOutput(combinedOutput) } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                .buttonStyle(.plain)
                .help("출력을 클립보드에 복사")
                Button { onShareToAgent(block) } label: {
                    Image(systemName: "paperplane")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                .buttonStyle(.plain)
                .help("이 결과를 agent 메시지에 첨부")
                Button { onRerun(block.command) } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.Color.accent)
                }
                .buttonStyle(.plain)
                .help("같은 명령 재실행")
            }
            Text("\(block.durationMs)ms")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
            if block.exitCode != 0 {
                Text("exit \(block.exitCode)")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 4)
    }

    private var combinedOutput: String {
        var parts: [String] = ["$ \(block.command)"]
        if !block.stdout.isEmpty { parts.append(block.stdout) }
        if !block.stderr.isEmpty { parts.append("--- stderr ---\n\(block.stderr)") }
        return parts.joined(separator: "\n")
    }

    private func outputView(_ text: String, isStderr: Bool) -> some View {
        ScrollView {
            Text(text)
                .font(Theme.Typography.monoSmall)
                .foregroundStyle(isStderr ? .red.opacity(0.85) : Theme.Color.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 4)
        }
        .frame(maxHeight: 200)
        .background(Theme.Color.bg.opacity(0.5))
    }
}
