import SwiftUI
import YuminaiCore
import YuminaiUI

// MARK: - Walk-through View (ADR-051)

/// 완료 task의 step-by-step 검토 view (Antigravity walk-through pattern).
///
/// **사용 시나리오**:
/// - 사용자가 큰 task 완료 후 "이 task 진행 과정 보여줘"
/// - TaskGraphMiniMap에서 completed task 클릭
/// - 관련 ConversationEntry들을 step별 분리 + 시간순 표시
///
/// **단계 분류**:
/// 1. 작업 시작 (task 정보)
/// 2. 사용자 입력
/// 3. agent 응답 (모델별 분리)
/// 4. system messages (handoff, routing 등)
/// 5. 최종 결과 (task.output)
struct WalkthroughSheet: View {
    let task: HarnessTask
    let allEntries: [ConversationEntry]
    let onClose: () -> Void

    @State private var selectedStepIndex: Int = 0

    private var taskEntries: [ConversationEntry] {
        // task.entryRefs가 비어있으면 task createdAt 이후의 모든 entry
        if !task.entryRefs.isEmpty {
            return allEntries.filter { task.entryRefs.contains($0.id) }
        }
        return allEntries.filter { $0.timestamp >= task.createdAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                stepNavigator.frame(width: 200)
                Divider()
                stepDetail
            }
            Divider()
            footer
        }
        .yuminaiSheetFrame(width: 720, height: 540, wrapInScrollView: false)
        .background(Theme.Color.bg)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.stack.fill.badge.person.crop")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Color.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Walk-through — \(task.title)")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.text)
                Text(task.description)
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            statusBadge
        }
        .padding(Theme.Spacing.lg)
    }

    private var statusBadge: some View {
        let (icon, color, label): (String, Color, String) = {
            switch task.status {
            case .pending: return ("circle.dotted", .gray, "대기")
            case .running: return ("circle.dashed", .green, "진행 중")
            case .completed: return ("checkmark.circle.fill", .green, "완료")
            case .failed: return ("xmark.circle.fill", .red, "실패")
            }
        }()
        return HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(label)
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.text)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private var stepNavigator: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Text("진행 단계 (\(taskEntries.count))")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.sm)
                ForEach(Array(taskEntries.enumerated()), id: \.element.id) { idx, entry in
                    Button {
                        selectedStepIndex = idx
                    } label: {
                        HStack(spacing: 6) {
                            stepIcon(entry: entry, index: idx)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(stepLabel(entry: entry, index: idx))
                                    .font(Theme.Typography.small)
                                    .foregroundStyle(idx == selectedStepIndex ? Theme.Color.text : Theme.Color.textSecondary)
                                    .lineLimit(1)
                                Text(timeLabel(entry.timestamp))
                                    .font(Theme.Typography.micro)
                                    .foregroundStyle(Theme.Color.textTertiary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, 6)
                        .background(idx == selectedStepIndex ? Theme.Color.accentMuted : Color.clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var stepDetail: some View {
        if taskEntries.isEmpty {
            EmptyStateHint(
                icon: "doc.text.magnifyingglass",
                title: "이 task와 연관된 대화가 없어요",
                message: "task 시작 후 진행이 없거나, 이미 완료되어 entry가 사라졌어요."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if selectedStepIndex < taskEntries.count {
            let entry = taskEntries[selectedStepIndex]
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    HStack {
                        stepIcon(entry: entry, index: selectedStepIndex)
                        Text(stepLabel(entry: entry, index: selectedStepIndex))
                            .font(Theme.Typography.title)
                            .foregroundStyle(Theme.Color.text)
                        Spacer()
                        Text(timeLabel(entry.timestamp))
                            .font(Theme.Typography.monoSmall)
                            .foregroundStyle(Theme.Color.textTertiary)
                    }
                    Text(entry.content)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Color.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let tokens = entry.tokenCount {
                        Text("\(tokens) output tokens")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.textTertiary)
                    }
                    if !entry.attachments.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("첨부")
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Color.textTertiary)
                            ForEach(entry.attachments, id: \.self) { att in
                                Text("@\(att)")
                                    .font(Theme.Typography.monoSmall)
                                    .foregroundStyle(Theme.Color.accent)
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.lg)
            }
        }
    }

    @ViewBuilder
    private func stepIcon(entry: ConversationEntry, index: Int) -> some View {
        switch entry.role {
        case .user:
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Color.accent)
        case .agent:
            if let kind = entry.agentKind {
                AgentBadge(agent: kind, size: .medium)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Color.accent)
            }
        case .system:
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }

    private func stepLabel(entry: ConversationEntry, index: Int) -> String {
        let prefix = "Step \(index + 1)"
        switch entry.role {
        case .user: return "\(prefix): 사용자 입력"
        case .agent:
            let kind = entry.agentKind?.shortLabel.capitalized ?? "Agent"
            return "\(prefix): \(kind) 응답"
        case .system: return "\(prefix): 시스템 메시지"
        }
    }

    private func timeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private var footer: some View {
        HStack {
            if let output = task.output, !output.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("최종 결과")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                    Text(output)
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.text)
                        .lineLimit(2)
                }
            }
            Spacer()
            FlatButton("닫기", variant: .secondary) { onClose() }
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(Theme.Spacing.md)
    }
}

// MARK: - Harness Help Sheet (ADR-051)

/// Harness 사용성 도움말 (ADR-051).
///
/// 친절한 cheatsheet — 단축키 / 명령 / 패턴 / FAQ 한 곳에.
struct HarnessHelpSheet: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    introSection
                    shortcutsSection
                    commandsSection
                    patternsSection
                    faqSection
                }
                .padding(Theme.Spacing.lg)
            }
            Divider()
            footer
        }
        .yuminaiSheetFrame(width: 640, height: 600, wrapInScrollView: false)
        .background(Theme.Color.bg)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.yellow)
            Text("Harness 도움말")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Color.text)
            Spacer()
        }
        .padding(Theme.Spacing.lg)
    }

    private var introSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Harness란?")
                .font(Theme.Typography.body.weight(.semibold))
                .foregroundStyle(Theme.Color.text)
            Text("다양한 LLM 모델 (Claude/Codex)을 단일 워크스페이스 컨텍스트에서 자연스럽게 오가도록 설계된 오케스트레이션 layer입니다. 사용자는 모델 차이를 의식하지 않고 task에 집중할 수 있어요.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("주요 단축키")
                .font(Theme.Typography.body.weight(.semibold))
                .foregroundStyle(Theme.Color.text)
            HelpRow(keys: ["⌘", "K"], description: "Command Palette — 모든 harness action 한 곳에서 검색")
            HelpRow(keys: ["⌘", "P"], description: "파일 빠른 검색")
            HelpRow(keys: ["⌘", "/"], description: "전체 단축키 도움말")
            HelpRow(keys: ["⌘", "D"], description: "사용량 대시보드")
            HelpRow(keys: ["esc"], description: "자동 routing 취소 (countdown 중)")
        }
    }

    private var commandsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Telegram 명령")
                .font(Theme.Typography.body.weight(.semibold))
                .foregroundStyle(Theme.Color.text)
            CommandHelp(cmd: "/model claude|codex", desc: "active pane 전환")
            CommandHelp(cmd: "/model auto", desc: "자동 routing 토글 (keyword 기반)")
            CommandHelp(cmd: "/model status", desc: "현재 모델 + routing 상태")
            CommandHelp(cmd: "/decompose <설명>", desc: "큰 task를 sub-task로 LLM 자동 분해")
            CommandHelp(cmd: "/use <name>", desc: "활성 워크스페이스 변경 (bind 유지)")
            CommandHelp(cmd: "/diff", desc: "보류 중인 변경사항 chunked 전송")
            CommandHelp(cmd: "/changes", desc: "변경 파일 목록 요약")
        }
    }

    private var patternsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("핵심 사용 패턴")
                .font(Theme.Typography.body.weight(.semibold))
                .foregroundStyle(Theme.Color.text)
            PatternHelp(
                title: "1. Manager mode (Antigravity)",
                desc: "당신은 supervisor. agent는 worker. /decompose로 분해 → TaskGraph에서 ▶ 실행"
            )
            PatternHelp(
                title: "2. 자동 routing (XAI explainable)",
                desc: "Settings에서 활성. ‘구현해줘’ → Codex / ‘리뷰’ → Claude. 3초 cancel window"
            )
            PatternHelp(
                title: "3. ProjectProfile 자동 inject",
                desc: "워크스페이스 만들 때 platform/언어 선택 → 모든 모델에 system context 자동 prepend"
            )
            PatternHelp(
                title: "4. SharedLog (단일 timeline)",
                desc: "Inspector ‘Harness’ 탭 — 모든 모델 응답이 단일 timeline. 모델 전환도 system entry로 표시"
            )
            PatternHelp(
                title: "5. 외부 vibe-coding (Telegram)",
                desc: "/bind <워크스페이스> 후 모바일에서 명령. 외부 turn은 자동 plan-mode로 안전 보호"
            )
        }
    }

    private var faqSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("자주 묻는 질문")
                .font(Theme.Typography.body.weight(.semibold))
                .foregroundStyle(Theme.Color.text)
            FaqItem(
                q: "Q. 자동 routing이 잘못 판단하면?",
                a: "3초 cancel window에서 Esc 또는 ‘취소’ 버튼. 또는 Settings에서 routing 끄고 /model claude/codex 명시 사용."
            )
            FaqItem(
                q: "Q. 같은 모델로 계속 쓰면 토큰 절약?",
                a: "예. Anthropic prompt cache가 같은 system context를 반복 사용 시 hit. ProjectProfile + handoff prompt가 cache-friendly."
            )
            FaqItem(
                q: "Q. TaskGraph 분해는 비용이?",
                a: "/decompose 1회 = 분해 prompt + JSON 응답 (~2-3K tokens). active session 컨텍스트에 들어가므로 그 turn은 Claude 호출 1회."
            )
            FaqItem(
                q: "Q. inline mode와 multi-pane mode 차이?",
                a: "inline: 모든 모델 응답을 단일 timeline으로 (Antigravity 패턴). multi-pane: 모델별 분리 chat (전통). Settings에서 토글."
            )
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            FlatButton("닫기", variant: .primary) { onClose() }
                .keyboardShortcut(.return, modifiers: [])
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(Theme.Spacing.md)
    }
}

private struct HelpRow: View {
    let keys: [String]
    let description: String
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(keys.enumerated()), id: \.offset) { idx, key in
                Text(key)
                    .font(Theme.Typography.monoSmall)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                if idx < keys.count - 1 {
                    Text("+").font(Theme.Typography.micro).foregroundStyle(Theme.Color.textTertiary)
                }
            }
            Text(description)
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
            Spacer()
        }
    }
}

private struct CommandHelp: View {
    let cmd: String
    let desc: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(cmd)
                .font(Theme.Typography.monoSmall)
                .foregroundStyle(Theme.Color.accent)
                .frame(minWidth: 180, alignment: .leading)
            Text(desc)
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
            Spacer()
        }
    }
}

private struct PatternHelp: View {
    let title: String
    let desc: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.Typography.small.weight(.medium))
                .foregroundStyle(Theme.Color.text)
            Text(desc)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }
}

private struct FaqItem: View {
    let q: String
    let a: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(q)
                .font(Theme.Typography.small.weight(.medium))
                .foregroundStyle(Theme.Color.text)
            Text(a)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }
}
