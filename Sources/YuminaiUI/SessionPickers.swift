import SwiftUI
import YuminaiCore

/// Composer footer 모델 picker — Claude Code 스타일 PickerMenu.
public struct ModelPicker: View {
    @Binding public var selection: ClaudeModel
    public var onChange: (ClaudeModel) -> Void

    public init(selection: Binding<ClaudeModel>, onChange: @escaping (ClaudeModel) -> Void = { _ in }) {
        self._selection = selection
        self.onChange = onChange
    }

    public var body: some View {
        PickerMenu(
            sections: [
                PickerSection(
                    title: "모델",
                    shortcutHint: ["⇧", "⌘", "M"],
                    items: ClaudeModel.allCases.enumerated().map { idx, model in
                        PickerItem(
                            label: model.displayName,
                            subtitle: model.subtitle,
                            isSelected: model == selection,
                            shortcutHint: "\(idx + 1)"
                        ) {
                            selection = model
                            onChange(model)
                        }
                    }
                )
            ]
        ) {
            PickerTriggerLabel(label: "모델", value: selection.rawValue)
        }
    }
}

/// 권한 모드 picker.
public struct ModePicker: View {
    @Binding public var selection: PermissionMode
    public var onChange: (PermissionMode) -> Void

    public init(selection: Binding<PermissionMode>, onChange: @escaping (PermissionMode) -> Void = { _ in }) {
        self._selection = selection
        self.onChange = onChange
    }

    public var body: some View {
        PickerMenu(
            sections: [
                PickerSection(
                    title: "권한 모드",
                    items: PermissionMode.allCases.map { mode in
                        PickerItem(
                            label: mode.displayName,
                            subtitle: mode.shortDescription,
                            isSelected: mode == selection
                        ) {
                            selection = mode
                            onChange(mode)
                        }
                    }
                )
            ],
            menuWidth: 320
        ) {
            PickerTriggerLabel(label: "권한", value: selection.rawValue)
        }
    }
}

/// 추론 강도 picker.
public struct EffortPicker: View {
    @Binding public var selection: EffortLevel
    public var onChange: (EffortLevel) -> Void

    public init(selection: Binding<EffortLevel>, onChange: @escaping (EffortLevel) -> Void = { _ in }) {
        self._selection = selection
        self.onChange = onChange
    }

    public var body: some View {
        PickerMenu(
            sections: [
                PickerSection(
                    title: "작업량",
                    shortcutHint: ["⇧", "⌘", "E"],
                    items: EffortLevel.allCases.map { level in
                        PickerItem(
                            label: level.displayName,
                            subtitle: level.shortDescription,
                            isSelected: level == selection
                        ) {
                            selection = level
                            onChange(level)
                        }
                    }
                )
            ]
        ) {
            PickerTriggerLabel(label: "강도", value: selection.rawValue)
        }
    }
}

// MARK: - Trigger label (Composer footer 안의 inline button)

struct PickerTriggerLabel: View {
    let label: String
    let value: String

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .foregroundStyle(Theme.Color.textTertiary)
            Text("·")
                .foregroundStyle(Theme.Color.textTertiary)
            Text(value)
                .foregroundStyle(Theme.Color.text)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(hovering ? Theme.Color.accent : Theme.Color.textTertiary)
                .padding(.leading, 1)
        }
        .font(Theme.Typography.label)
        .padding(.horizontal, Theme.Spacing.md - 2)
        .padding(.vertical, Theme.Spacing.xs + 1)
        .background(hovering ? Theme.Color.surfaceHi : .clear)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .animation(.easeOut(duration: 0.10), value: hovering)
        .onHover { hovering = $0 }
    }
}
