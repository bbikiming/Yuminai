import SwiftUI

/// 단축키 도움말 — 모든 단축키 카테고리별 정리 (C1).
public struct ShortcutHelpSheet: View {
    public let onClose: () -> Void

    public init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            FlatHDivider()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    ForEach(Self.categories) { cat in
                        categorySection(cat)
                    }
                }
                .padding(Theme.Spacing.lg)
            }
        }
        .frame(width: 520, height: 560)
        .background(Theme.Color.bg)
    }

    private var header: some View {
        HStack {
            Text("단축키")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Color.text)
            Spacer()
            FlatButton("닫기", variant: .secondary, size: .small, action: onClose)
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(Theme.Spacing.lg)
    }

    @ViewBuilder
    private func categorySection(_ cat: ShortcutCategory) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(cat.title)
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Color.textSecondary)
                .textCase(.uppercase)
                .tracking(0.6)
            VStack(spacing: 1) {
                ForEach(cat.shortcuts) { sc in
                    shortcutRow(sc)
                }
            }
            .background(Theme.Color.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(Theme.Color.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        }
    }

    private func shortcutRow(_ sc: ShortcutEntry) -> some View {
        HStack {
            Text(sc.label)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Color.text)
            Spacer()
            HStack(spacing: 3) {
                ForEach(sc.keys, id: \.self) { key in
                    ShortcutKeyBadge(key)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
    }

    static let categories: [ShortcutCategory] = [
        ShortcutCategory(title: "글로벌", shortcuts: [
            .init(label: "새 워크스페이스", keys: ["⌘", "N"]),
            .init(label: "사이드바 토글", keys: ["⌘", "⌥", "1"]),
            .init(label: "Inspector 토글", keys: ["⌘", "⌥", "I"]),
            .init(label: "사용량 대시보드", keys: ["⌘", "D"]),
            .init(label: "설정", keys: ["⌘", ","]),
            .init(label: "단축키 도움말 (이 화면)", keys: ["⌘", "/"]),
            .init(label: "워크스페이스 빠른 전환", keys: ["⌘", "1~9"])
        ]),
        ShortcutCategory(title: "채팅", shortcuts: [
            .init(label: "메시지 보내기", keys: ["⌘", "↵"]),
            .init(label: "응답 중단", keys: ["esc"])
        ]),
        ShortcutCategory(title: "노트 편집", shortcuts: [
            .init(label: "저장", keys: ["⌘", "S"])
        ])
    ]
}

public struct ShortcutCategory: Identifiable {
    public let id = UUID()
    public let title: String
    public let shortcuts: [ShortcutEntry]
}

public struct ShortcutEntry: Identifiable {
    public let id = UUID()
    public let label: String
    public let keys: [String]
}
