import SwiftUI
import AppKit
import YuminaiCore
import YuminaiUI

/// **ADR-104** — 첫 실행 설치 wizard sheet.
///
/// onboarding 완료 후 자동 표시. 도구 3종(Claude Code / Codex CLI / cokacdir)의
/// 설치 상태를 검사하고, Terminal.app 자동 열기 또는 명령 복사를 안내한다.
///
/// 보안 정책:
/// - Yuminai가 `bash -c "curl | bash"`를 직접 실행하지 않는다.
/// - Terminal.app에 명령을 붙여 넣기만 하며, 사용자가 직접 Enter를 눌러야 한다.
struct SetupWizardSheet: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var bindable = appModel

        VStack(spacing: 0) {
            // MARK: 헤더
            HStack {
                Label("Yuminai 시작하기", systemImage: "sparkles")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.text)
                Spacer()
                Button("건너뛰기") {
                    appModel.dismissSetupWizard(markCompleted: false)
                }
                .buttonStyle(.plain)
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
                .accessibilityLabel("설정 건너뛰기. 다음 실행 시 다시 표시됩니다.")
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.top, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.md)

            Divider()

            // MARK: 본문
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text("Yuminai를 사용하려면 아래 도구를 설치하세요.\n자동 설치 또는 직접 명령을 복사해 터미널에서 실행할 수 있어요.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(SetupTool.allCases) { tool in
                        SetupToolCard(
                            tool: tool,
                            status: appModel.setupToolStatus[tool] ?? .unknown
                        )
                    }

                    InfoCallout(tone: .info) {
                        Text("팁: 자동 실행은 Terminal.app에 명령을 붙여 넣고 여러분이 Enter를 누르도록 안내합니다. 안전을 위해 명령을 직접 확인할 수 있어요.")
                            .font(Theme.Typography.small)
                            .foregroundStyle(Theme.Color.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Theme.Spacing.xl)
            }

            Divider()

            // MARK: 푸터 액션
            HStack {
                FlatButton("다시 검사", icon: "arrow.clockwise", variant: .secondary) {
                    Task { await appModel.refreshSetupStatus() }
                }
                Spacer()
                FlatButton("완료", variant: .primary) {
                    appModel.dismissSetupWizard(markCompleted: true)
                }
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.md)
        }
        .frame(width: 620, height: 680)
        .background(Theme.Color.bg)
        .task {
            // 시트가 열릴 때 즉시 검사
            if appModel.setupToolStatus.isEmpty {
                await appModel.refreshSetupStatus()
            }
        }
    }
}

// MARK: - SetupToolCard

/// 도구 한 종을 나타내는 카드 (아이콘, 상태 배지, 설명, 설치 명령, 액션 버튼).
private struct SetupToolCard: View {
    let tool: SetupTool
    let status: SetupChecker.InstallStatus

    @State private var commandCopied: Bool = false

    var body: some View {
        CardSection(style: .subtle) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                // MARK: 헤더 행
                HStack(spacing: Theme.Spacing.sm) {
                    // 아이콘
                    ZStack {
                        Circle()
                            .fill(iconTint.opacity(0.12))
                            .frame(width: 32, height: 32)
                        Image(systemName: tool.iconName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(iconTint)
                    }
                    .accessibilityHidden(true)

                    // 이름 + 배지
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(tool.displayName)
                            .font(Theme.Typography.body.weight(.semibold))
                            .foregroundStyle(Theme.Color.text)
                        badgeView(for: tool)
                    }

                    Spacer()

                    // 설치 상태 배지
                    statusBadge
                }

                // MARK: 설명
                Text(tool.purpose)
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // MARK: 설치 명령 (미설치 / unknown 시에만 전체 표시)
                if case .installed = status { } else {
                    commandBlock
                }

                // MARK: cokacdir 전용: cokacctl 사용법 안내
                if tool == .cokacdir {
                    cokacdirUsageGuide
                }

                // MARK: 공식 문서 링크
                HStack {
                    Spacer()
                    Button {
                        NSWorkspace.shared.open(tool.docsURL)
                    } label: {
                        Label("공식 문서", systemImage: "arrow.up.right.square")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(tool.displayName) 공식 문서 열기")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(tool.displayName) — \(tool.badgeLabel)")
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var commandBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            // 명령 텍스트
            Text(tool.installCommand)
                .font(Theme.Typography.monoSmall)
                .foregroundStyle(Theme.Color.text)
                .textSelection(.enabled)
                .padding(Theme.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Color.surfaceHi)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

            // 액션 버튼
            HStack(spacing: Theme.Spacing.sm) {
                FlatButton(
                    commandCopied ? "복사됨" : "복사",
                    icon: commandCopied ? "checkmark" : "doc.on.doc",
                    variant: .secondary,
                    size: .small
                ) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(tool.installCommand, forType: .string)
                    withAnimation(.easeInOut(duration: 0.2)) { commandCopied = true }
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        withAnimation(.easeInOut(duration: 0.2)) { commandCopied = false }
                    }
                }

                FlatButton("터미널에서 실행", icon: "terminal", variant: .secondary, size: .small) {
                    runInTerminal(tool.installCommand)
                }
                .accessibilityHint("Terminal.app에 명령을 붙여 넣습니다. Enter는 직접 눌러야 합니다.")
            }
        }
    }

    @ViewBuilder
    private var cokacdirUsageGuide: some View {
        ExpandableInfoSection(label: "설치 후 cokacctl 사용법", labelIcon: "info.circle") {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                cokacdirKeyRow(key: "i", description: "cokacdir 설치")
                cokacdirKeyRow(key: "k", description: "봇 토큰 등록")
                cokacdirKeyRow(key: "s", description: "서버 시작")
            }
            .padding(.top, Theme.Spacing.xs)
        }
    }

    private func cokacdirKeyRow(key: String, description: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(key)
                .font(Theme.Typography.monoSmall.weight(.bold))
                .foregroundStyle(Theme.Color.text)
                .frame(width: 22, height: 22)
                .background(Theme.Color.surfaceHi)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .stroke(Theme.Color.borderSubtle, lineWidth: 0.5)
                )
            Text("→ \(description)")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch status {
        case .installed:
            Label("설치됨", systemImage: "checkmark.circle.fill")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.success)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Theme.Color.success.opacity(0.10))
                .clipShape(Capsule())
        case .notInstalled:
            Label("미설치", systemImage: "exclamationmark.circle.fill")
                .font(Theme.Typography.micro)
                .foregroundStyle(.orange)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.orange.opacity(0.10))
                .clipShape(Capsule())
        case .unknown:
            Label("확인 중", systemImage: "ellipsis.circle.fill")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Theme.Color.surfaceHi)
                .clipShape(Capsule())
        }
    }

    private var iconTint: Color {
        switch tool {
        case .claudeCode: return Theme.Color.accent
        case .codexCLI: return .green
        case .cokacdir: return .blue
        }
    }

    @ViewBuilder
    private func badgeView(for tool: SetupTool) -> some View {
        let (fg, bg): (Color, Color) = {
            switch tool {
            case .claudeCode: return (Theme.Color.danger, Theme.Color.danger.opacity(0.10))
            case .codexCLI: return (Theme.Color.textTertiary, Theme.Color.surfaceHi)
            case .cokacdir: return (.blue, Color.blue.opacity(0.10))
            }
        }()

        Text(tool.badgeLabel)
            .font(Theme.Typography.micro)
            .foregroundStyle(fg)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(bg)
            .clipShape(Capsule())
    }

    // MARK: - Terminal 자동 실행 (AppleScript)
    // 보안 정책: 명령을 Terminal.app에 붙여 넣기만 함. 사용자가 Enter를 직접 눌러야 실행됨.

    private func runInTerminal(_ command: String) {
        let escapedCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "\(escapedCommand)"
        end tell
        """
        // 클립보드에도 복사 (fallback)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
}
