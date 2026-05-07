import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-079 Phase 5** — Git commit sheet (Claude Code 패턴 단순화).
///
/// 흐름:
/// 1. 변경 사항 요약 표시 (DirtyStats)
/// 2. 자동 생성된 commit message (사용자 수정 가능)
/// 3. Co-Authored-By 자동 footer (Claude 표기)
/// 4. 1-click commit + 결과 토스트
struct GitCommitSheet: View {
    let branch: String
    let stats: DirtyStats
    let onCommit: (_ message: String) -> Void
    let onCancel: () -> Void
    /// **ADR-081 Phase 2** — AI 메시지 생성 콜백 (nil = AI 생성 비활성).
    let onGenerateWithAI: (() async -> String?)?

    @State private var message: String = ""
    @State private var generatingAI: Bool = false
    @FocusState private var inputFocused: Bool

    init(
        branch: String,
        stats: DirtyStats,
        onCommit: @escaping (String) -> Void,
        onCancel: @escaping () -> Void,
        onGenerateWithAI: (() async -> String?)? = nil
    ) {
        self.branch = branch
        self.stats = stats
        self.onCommit = onCommit
        self.onCancel = onCancel
        self.onGenerateWithAI = onGenerateWithAI
    }

    var body: some View {
        YuminaiSheet(width: 540, height: 420) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                statsCard
                messageField
                footerHint
            }
            .padding(Theme.Spacing.xl)
        } footer: {
            HStack {
                Spacer()
                FlatButton("취소", variant: .secondary, action: onCancel)
                    .keyboardShortcut(.escape, modifiers: [])
                FlatButton("커밋", icon: "checkmark.circle.fill", variant: .primary) {
                    onCommit(message)
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(stats.isEmpty)
            }
        }
        .onAppear {
            // 자동 생성된 default message
            message = AutoCommitMessageGenerator.generate(stats: stats)
            inputFocused = true
        }
        .overlay(alignment: .topTrailing) {
            SheetCloseButton(action: onCancel)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(Theme.Color.accent)
                    .accessibilityHidden(true)
                Text("Git 커밋 만들기")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.text)
            }
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Color.textSecondary)
                    .accessibilityHidden(true)
                Text(branch)
                    .font(Theme.Typography.monoSmall)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
        }
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("변경 사항")
            HStack(spacing: Theme.Spacing.lg) {
                if stats.modified > 0 {
                    statBlock(label: "수정", value: "\(stats.modified)", color: .yellow)
                }
                if stats.added > 0 {
                    statBlock(label: "추가", value: "\(stats.added)", color: .green)
                }
                if stats.deleted > 0 {
                    statBlock(label: "삭제", value: "\(stats.deleted)", color: .red)
                }
                if stats.untracked > 0 {
                    statBlock(label: "추적 안 됨", value: "\(stats.untracked)", color: .gray)
                }
                if stats.isEmpty {
                    Text("변경된 파일이 없어요. 먼저 파일을 수정한 후 다시 시도하세요.")
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                Spacer()
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private func statBlock(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
                .textCase(.uppercase)
            Text(value)
                .font(Theme.Typography.title)
                .foregroundStyle(color)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)개")
    }

    private var messageField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                sectionLabel("커밋 메시지")
                Spacer()
                // ADR-081 Phase 2 — AI 메시지 생성 버튼
                if let generate = onGenerateWithAI {
                    Button {
                        Task {
                            generatingAI = true
                            defer { generatingAI = false }
                            if let aiMessage = await generate() {
                                message = aiMessage
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if generatingAI {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 9))
                            }
                            Text(generatingAI ? "생성 중…" : "AI로 생성")
                                .font(Theme.Typography.micro.weight(.medium))
                        }
                        .foregroundStyle(Theme.Color.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.Color.accentMuted)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(generatingAI || stats.isEmpty)
                    .help("Claude가 git diff를 분석해 commit message 생성")
                    .accessibilityLabel("AI로 커밋 메시지 생성")
                }
            }
            FlatTextField("예: feat: 사용자 인증 추가", text: $message)
                .focused($inputFocused)
                .accessibilityLabel("커밋 메시지")
                .accessibilityHint("자동 생성된 메시지를 수정할 수 있어요. 우상단 'AI로 생성' 버튼으로 Claude가 diff 분석.")
        }
    }

    private var footerHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(Theme.Color.textTertiary)
                .accessibilityHidden(true)
            Text("모든 변경사항이 자동으로 staging됩니다. Co-Authored-By: Claude (Yuminai)가 자동 추가됩니다.")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.micro)
            .foregroundStyle(Theme.Color.textTertiary)
            .textCase(.uppercase)
            .tracking(0.6)
    }
}
