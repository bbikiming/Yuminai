import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-086 Phase 1** — 텔레그램 에러 로그 viewer sheet.
///
/// 표시:
/// - 카테고리별 통계 chart (auth/rateLimit/network/server/parsing/other)
/// - 최근 N개 에러 (역순)
/// - 사용자 친화적 한국어 메시지 + 디버그용 raw message (toggle)
struct TelegramErrorLogSheet: View {
    @Environment(AppModel.self) private var appModel
    @State private var entries: [TelegramErrorEntry] = []
    @State private var stats: [TelegramErrorEntry.Category: Int] = [:]
    @State private var loading: Bool = true
    @State private var showRawMessages: Bool = false

    var body: some View {
        YuminaiSheet(width: 720, height: 600) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                statsCard
                Divider()
                entryList
            }
            .padding(Theme.Spacing.xl)
        } footer: {
            HStack {
                Text("\(entries.count)개 에러")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                Spacer()
                Toggle("Raw 메시지", isOn: $showRawMessages)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .accessibilityLabel("Raw 디버그 메시지 표시")
                Button("초기화", role: .destructive) {
                    Task {
                        await appModel.telegramClearErrorLog()
                        await reload()
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Color.danger)
                .padding(.horizontal, 8)
                FlatButton("닫기", variant: .secondary) {
                    appModel.showTelegramErrorLogSheet = false
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .task { await reload() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.bubble.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text("텔레그램 에러 로그")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.text)
            }
            Text("최근 발생한 텔레그램 통신 오류. 카테고리별 통계로 패턴 파악 가능.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("카테고리별 통계")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
                .textCase(.uppercase)
                .tracking(0.6)
            if stats.isEmpty {
                Text("에러 없음 ✓")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.success)
            } else {
                HStack(spacing: 12) {
                    ForEach([TelegramErrorEntry.Category.auth, .rateLimit, .network, .server, .parsing, .other], id: \.self) { cat in
                        if let count = stats[cat], count > 0 {
                            statBadge(category: cat, count: count)
                        }
                    }
                    Spacer()
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private func statBadge(category: TelegramErrorEntry.Category, count: Int) -> some View {
        let color = categoryColor(category)
        return VStack(alignment: .leading, spacing: 2) {
            Text(categoryLabel(category))
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
                .textCase(.uppercase)
            Text("\(count)")
                .font(Theme.Typography.title)
                .foregroundStyle(color)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(categoryLabel(category)) \(count)개")
    }

    @ViewBuilder
    private var entryList: some View {
        if loading {
            HStack { Spacer(); ProgressView(); Spacer() }
                .frame(maxHeight: .infinity)
        } else if entries.isEmpty {
            EmptyStateHint(
                icon: "checkmark.circle",
                title: "에러 없음",
                message: "최근 텔레그램 통신 오류가 없어요. 정상 동작 중."
            )
            .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(entries) { entry in
                        entryRow(entry)
                    }
                }
            }
        }
    }

    private func entryRow(_ entry: TelegramErrorEntry) -> some View {
        let color = categoryColor(entry.category)
        return HStack(alignment: .top, spacing: 8) {
            // 카테고리 dot
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .padding(.top, 4)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(categoryLabel(entry.category))
                        .font(Theme.Typography.micro.weight(.semibold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(color.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    Text(formatDate(entry.timestamp))
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                    Spacer()
                }
                Text(entry.userFacingMessage)
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.text)
                    .fixedSize(horizontal: false, vertical: true)
                if showRawMessages {
                    Text(entry.message)
                        .font(Theme.Typography.codeBlock)
                        .foregroundStyle(Theme.Color.textTertiary)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .textSelection(.enabled)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(categoryLabel(entry.category)) 에러: \(entry.userFacingMessage)")
    }

    private func categoryLabel(_ cat: TelegramErrorEntry.Category) -> String {
        switch cat {
        case .auth: return "인증"
        case .rateLimit: return "한도 초과"
        case .network: return "네트워크"
        case .server: return "서버"
        case .parsing: return "파싱"
        case .other: return "기타"
        }
    }

    private func categoryColor(_ cat: TelegramErrorEntry.Category) -> Color {
        switch cat {
        case .auth: return Theme.Color.danger
        case .rateLimit: return .orange
        case .network: return .blue
        case .server: return .purple
        case .parsing: return Theme.Color.warning
        case .other: return Theme.Color.textSecondary
        }
    }

    private func formatDate(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "방금 전" }
        if interval < 3600 { return "\(Int(interval / 60))분 전" }
        if interval < 86400 { return "\(Int(interval / 3600))시간 전" }
        return "\(Int(interval / 86400))일 전"
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        async let entriesTask = appModel.telegramRecentErrors(limit: 50)
        async let statsTask = appModel.telegramErrorStats()
        entries = await entriesTask
        stats = await statsTask
    }
}
