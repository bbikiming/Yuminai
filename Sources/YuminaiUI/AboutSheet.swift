import SwiftUI
import YuminaiCore

/// **ADR-068 Phase 2** — About sheet (버전 + 로고 + ADR 통계 + credits).
public struct AboutSheet: View {
    public let appVersion: String
    public let buildNumber: String
    /// ADR 통계 (이번 세션 누적)
    public let adrCount: Int
    public let testCount: Int
    public let onClose: () -> Void

    public init(
        appVersion: String = "1.0.0-dev",
        buildNumber: String = "ADR-068",
        adrCount: Int = 17,
        testCount: Int = 495,
        onClose: @escaping () -> Void
    ) {
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.adrCount = adrCount
        self.testCount = testCount
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 24) {
            // Brand logo
            BrandLogo(size: 128)
                .padding(.top, 32)

            // App name + version
            VStack(spacing: 4) {
                Text("Yuminai")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Theme.Color.text)
                Text("v\(appVersion) · \(buildNumber)")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
            }

            // Tagline
            Text("다중 LLM 모델을 자연스럽게 오가는 vibe-coding workspace")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Divider().padding(.horizontal, 32)

            // Stats grid
            HStack(spacing: 24) {
                statBlock(value: "\(adrCount)", label: "ADRs", color: Theme.Brand.accent)
                statBlock(value: "\(testCount)", label: "Tests", color: .green)
                statBlock(value: "12K+", label: "Lines", color: .indigo)
                statBlock(value: "32+", label: "Files", color: .purple)
            }

            Divider().padding(.horizontal, 32)

            // Credits
            VStack(alignment: .leading, spacing: 6) {
                Text("Built with")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .textCase(.uppercase)
                creditRow("Swift 6.2 + SwiftUI + SwiftData", icon: "swift")
                creditRow("Anthropic Claude Code SDK", icon: "sparkles")
                creditRow("OpenAI Codex CLI", icon: "chevron.left.forwardslash.chevron.right")
                creditRow("Telegram Bot API", icon: "paperplane")
                creditRow("SwiftUI Charts framework", icon: "chart.line.uptrend.xyaxis")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)

            Spacer()

            // Footer
            HStack {
                Text("© 2026 Yuminai · MIT License")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                Spacer()
                FlatButton("닫기", variant: .primary, action: onClose)
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(Theme.Spacing.md)
        }
        // ADR-073 — 반응형. About은 ScrollView 없어 wrap=true.
        .yuminaiSheetFrame(width: 480, height: 620, wrapInScrollView: true)
        .background(Theme.Color.bg)
        .overlay(alignment: .topTrailing) {
            SheetCloseButton(action: onClose)
        }
    }

    private func statBlock(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
                .textCase(.uppercase)
        }
        .frame(width: 80)
    }

    private func creditRow(_ text: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Theme.Brand.accent)
                .frame(width: 16)
            Text(text)
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.text)
            Spacer()
        }
    }
}
