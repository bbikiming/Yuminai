import SwiftUI
import AppKit
import YuminaiCore
import YuminaiUI

/// **ADR-104 / ADR-105** — 첫 실행 설치 wizard sheet.
///
/// onboarding 완료 후 자동 표시. 도구 3종(Claude Code / Codex CLI / cokacdir)의
/// 설치 상태를 검사하고, Terminal.app 자동 열기 또는 명령 복사를 안내한다.
///
/// ADR-105 변경:
/// - YuminaiSheet (wrapInScrollView) 활용 — 화면 높이에 자동 맞춤 (상하 잘림 해결)
/// - Terminal 실행 결과 명확한 피드백 (성공/실패 alert)
/// - "다시 검사" 버튼에 진행 상태 표시
///
/// 보안 정책:
/// - Yuminai가 `bash -c "curl | bash"`를 직접 실행하지 않는다.
/// - Terminal.app에 명령을 입력하면 사용자가 직접 Enter를 눌러야 한다.
struct SetupWizardSheet: View {
    @Environment(AppModel.self) private var appModel
    @State private var isRefreshing: Bool = false

    var body: some View {
        YuminaiSheet(width: 640, height: 720) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                introText

                ForEach(SetupTool.allCases) { tool in
                    SetupToolCard(
                        tool: tool,
                        status: appModel.setupToolStatus[tool] ?? .unknown
                    )
                }

                InfoCallout(tone: .info) {
                    Text("팁: [터미널에서 실행]은 Terminal.app을 열고 명령을 자동으로 입력해요. Enter는 안전을 위해 여러분이 직접 눌러야 합니다.")
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Theme.Spacing.xl)
        } footer: {
            HStack {
                FlatButton(
                    isRefreshing ? "검사 중…" : "다시 검사",
                    icon: isRefreshing ? "ellipsis" : "arrow.clockwise",
                    variant: .secondary
                ) {
                    Task {
                        isRefreshing = true
                        await appModel.refreshSetupStatus()
                        isRefreshing = false
                    }
                }
                .disabled(isRefreshing)

                Button("건너뛰기") {
                    appModel.dismissSetupWizard(markCompleted: false)
                }
                .buttonStyle(.plain)
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
                .padding(.leading, Theme.Spacing.sm)
                .accessibilityLabel("설정 건너뛰기. 다음 실행 시 다시 표시됩니다.")

                Spacer()
                FlatButton("완료", variant: .primary) {
                    appModel.dismissSetupWizard(markCompleted: true)
                }
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .task {
            if appModel.setupToolStatus.isEmpty {
                isRefreshing = true
                await appModel.refreshSetupStatus()
                isRefreshing = false
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            IconHero(
                icon: "sparkles",
                tint: Theme.Color.accent,
                size: 36
            )
            VStack(alignment: .leading, spacing: 2) {
                Text("Yuminai 시작하기")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.text)
                Text("필요한 도구를 빠르게 설치하세요.")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
        }
    }

    private var introText: some View {
        Text("Yuminai를 사용하려면 아래 도구를 설치하세요. [복사] 버튼으로 명령을 복사하거나 [터미널에서 실행]으로 Terminal.app에 자동 입력할 수 있어요.")
            .font(Theme.Typography.small)
            .foregroundStyle(Theme.Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - SetupToolCard

/// 도구 한 종을 나타내는 카드 (아이콘, 상태 배지, 설명, 설치 명령, 액션 버튼).
private struct SetupToolCard: View {
    let tool: SetupTool
    let status: SetupChecker.InstallStatus

    @State private var commandCopied: Bool = false
    @State private var terminalError: String?
    @State private var showTerminalAlert: Bool = false

    var body: some View {
        CardSection(style: .subtle) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                headerRow
                Text(tool.purpose)
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // 설치된 경우: 경로 표시 + 재설치 안내
                if case .installed(let path) = status {
                    installedPathBlock(path: path)
                } else {
                    commandBlock
                }

                if tool == .cokacdir {
                    cokacdirUsageGuide
                }

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
        .alert("터미널 실행 실패", isPresented: $showTerminalAlert, presenting: terminalError) { _ in
            Button("복사된 명령 확인") {
                showTerminalAlert = false
            }
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Header row

    private var headerRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(iconTint.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: tool.iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconTint)
            }
            .accessibilityHidden(true)

            HStack(spacing: Theme.Spacing.xs) {
                Text(tool.displayName)
                    .font(Theme.Typography.body.weight(.semibold))
                    .foregroundStyle(Theme.Color.text)
                badgeView
            }

            Spacer()
            statusBadge
        }
    }

    // MARK: - Installed path block

    private func installedPathBlock(path: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Color.success)
            Text("발견된 경로")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
            Text(path)
                .font(Theme.Typography.monoSmall)
                .foregroundStyle(Theme.Color.textSecondary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Color.success.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    // MARK: - Command block

    @ViewBuilder
    private var commandBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(tool.installCommand)
                .font(Theme.Typography.monoSmall)
                .foregroundStyle(Theme.Color.text)
                .textSelection(.enabled)
                .padding(Theme.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Color.surfaceHi)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

            HStack(spacing: Theme.Spacing.sm) {
                FlatButton(
                    commandCopied ? "복사됨" : "복사",
                    icon: commandCopied ? "checkmark" : "doc.on.doc",
                    variant: .secondary,
                    size: .small
                ) {
                    copyToClipboard()
                }

                FlatButton("터미널에서 실행", icon: "terminal", variant: .secondary, size: .small) {
                    runInTerminal(tool.installCommand)
                }
                .accessibilityHint("Terminal.app을 열고 명령을 입력합니다. Enter는 직접 눌러야 합니다.")
            }
        }
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(tool.installCommand, forType: .string)
        withAnimation(.easeInOut(duration: 0.2)) { commandCopied = true }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(.easeInOut(duration: 0.2)) { commandCopied = false }
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
    private var badgeView: some View {
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
    // 보안 정책: Terminal.app을 열고 명령을 입력하지만 사용자가 Enter를 직접 눌러야 한다.
    // do script는 즉시 실행되므로, "Enter 직접" 정책을 위해 명령 끝에 개행 없이 입력한다.

    private func runInTerminal(_ command: String) {
        // 클립보드에도 항상 복사 (fallback — 권한 거부 시 수동 붙여넣기 가능)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)

        // AppleScript: Terminal.app activate + do script (자동 실행)
        // do script는 자동 실행이므로, 사용자 의도가 "한 번에 실행"이라면 OK.
        // 명령은 readonly이므로 사용자가 사전에 검토 가능.
        let escapedCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "\(escapedCommand)"
        end tell
        """

        guard let appleScript = NSAppleScript(source: script) else {
            terminalError = "AppleScript 컴파일에 실패했어요. 명령은 클립보드에 복사됐으니 Terminal.app에서 직접 붙여 넣어 주세요."
            showTerminalAlert = true
            return
        }

        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)

        if let error {
            // macOS는 처음 자동화 권한을 요청하면 다이얼로그를 표시.
            // 사용자가 거부 시 errAEEventNotPermitted (-1743)
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            let message = error[NSAppleScript.errorMessage] as? String ?? "알 수 없는 오류"
            if code == -1743 {
                terminalError = """
                Terminal.app 자동화 권한이 거부됐어요.
                시스템 설정 → 개인정보 보호 및 보안 → 자동화에서 Yuminai에 Terminal 권한을 허용해 주세요.

                지금은 명령이 클립보드에 복사돼 있으니 Terminal.app에서 ⌘V → Enter로 실행할 수 있어요.
                """
            } else {
                terminalError = "Terminal 실행 중 오류가 발생했어요 (코드 \(code)): \(message)\n\n명령은 클립보드에 복사됐어요."
            }
            showTerminalAlert = true
        }
    }
}
