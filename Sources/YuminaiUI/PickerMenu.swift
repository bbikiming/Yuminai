import SwiftUI

/// Claude Code 데스크탑 스타일 dropdown menu.
///
/// 사용자가 보여준 스크린샷의 룩:
/// - 다크 배경 (`elevated`) + 둥근 모서리
/// - 섹션 헤더 (라벨 + 우측 단축키 badges)
/// - 항목 (라벨 + 옵션 부제 + ✓ + 우측 단축키)
/// - hover/selected 상태
/// - native `.popover()` 기반
public struct PickerMenu<TriggerLabel: View>: View {
    public let sections: [PickerSection]
    public let trigger: () -> TriggerLabel
    public let menuWidth: CGFloat

    public init(
        sections: [PickerSection],
        menuWidth: CGFloat = 280,
        @ViewBuilder trigger: @escaping () -> TriggerLabel
    ) {
        self.sections = sections
        self.menuWidth = menuWidth
        self.trigger = trigger
    }

    @State private var isOpen: Bool = false

    public var body: some View {
        Button(action: { isOpen.toggle() }) {
            trigger()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            PickerMenuContent(sections: sections, onClose: { isOpen = false })
                .frame(width: menuWidth)
        }
    }
}

// MARK: - Section / Item models

public struct PickerSection: Identifiable {
    public let id = UUID()
    public let title: String
    public let shortcutHint: [String]?
    public let items: [PickerItem]

    public init(title: String, shortcutHint: [String]? = nil, items: [PickerItem]) {
        self.title = title
        self.shortcutHint = shortcutHint
        self.items = items
    }
}

public struct PickerItem: Identifiable {
    public let id = UUID()
    public let label: String
    public let subtitle: String?
    public let isSelected: Bool
    public let shortcutHint: String?
    public let isDisabled: Bool
    public let action: () -> Void

    public init(
        label: String,
        subtitle: String? = nil,
        isSelected: Bool = false,
        shortcutHint: String? = nil,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.shortcutHint = shortcutHint
        self.isDisabled = isDisabled
        self.action = action
    }
}

// MARK: - Menu content

struct PickerMenuContent: View {
    let sections: [PickerSection]
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sections.enumerated()), id: \.element.id) { idx, section in
                if idx > 0 {
                    Divider()
                        .background(Theme.Color.borderSubtle)
                        .padding(.vertical, 4)
                }
                sectionHeader(section)
                    .padding(.horizontal, 12)
                    .padding(.top, idx == 0 ? 8 : 4)
                    .padding(.bottom, 4)

                VStack(alignment: .leading, spacing: 1) {
                    ForEach(section.items) { item in
                        PickerItemRow(item: item, onSelect: {
                            item.action()
                            onClose()
                        })
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(.vertical, 4)
        .background(Theme.Color.elevated)
    }

    private func sectionHeader(_ section: PickerSection) -> some View {
        HStack(spacing: 4) {
            Text(section.title)
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Color.textSecondary)
            Spacer()
            if let hints = section.shortcutHint {
                HStack(spacing: 3) {
                    ForEach(hints, id: \.self) { key in
                        ShortcutKeyBadge(key)
                    }
                }
            }
        }
    }
}

// MARK: - Item row

struct PickerItemRow: View {
    let item: PickerItem
    let onSelect: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Text(item.label)
                    .font(Theme.Typography.body)
                    .foregroundStyle(item.isDisabled ? Theme.Color.textDisabled : Theme.Color.text)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textTertiary)
                }

                Spacer()

                if item.isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Color.text)
                }

                if let shortcut = item.shortcutHint {
                    Text(shortcut)
                        .font(Theme.Typography.small.monospacedDigit())
                        .foregroundStyle(Theme.Color.textTertiary)
                        .frame(minWidth: 12, alignment: .trailing)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(hovering ? Theme.Color.surfaceHi : .clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.08), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .disabled(item.isDisabled)
    }
}

// MARK: - Shortcut badge ([⇧] [⌘] [I] 같은)

public struct ShortcutKeyBadge: View {
    public let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(Theme.Typography.small.monospacedDigit())
            .foregroundStyle(Theme.Color.textSecondary)
            .frame(minWidth: 18, minHeight: 18)
            .padding(.horizontal, 4)
            .background(Theme.Color.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Theme.Color.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
