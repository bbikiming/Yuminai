import SwiftUI
import YuminaiCore

/// 모델/모드/효과 picker 공통 룩 — Claude Code CLI 인스피레이션, 플랫 + monospace.
struct InlinePicker<Value: Hashable>: View {
    let label: String
    let value: Value
    let valueLabel: String
    let menu: () -> AnyView

    init(
        label: String,
        value: Value,
        valueLabel: String,
        @ViewBuilder menu: @escaping () -> some View
    ) {
        self.label = label
        self.value = value
        self.valueLabel = valueLabel
        self.menu = { AnyView(menu()) }
    }

    var body: some View {
        Menu {
            menu()
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .foregroundStyle(Theme.Color.textTertiary)
                Text("·")
                    .foregroundStyle(Theme.Color.textTertiary)
                Text(valueLabel)
                    .foregroundStyle(Theme.Color.text)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7))
                    .foregroundStyle(Theme.Color.textSecondary)
                    .padding(.leading, 2)
            }
            .font(Theme.Typography.label)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Color.bgPanel)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .stroke(Theme.Color.border, lineWidth: Theme.Stroke.hairline)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

public struct ModelPicker: View {
    @Binding public var selection: ClaudeModel
    public var onChange: (ClaudeModel) -> Void

    public init(selection: Binding<ClaudeModel>, onChange: @escaping (ClaudeModel) -> Void = { _ in }) {
        self._selection = selection
        self.onChange = onChange
    }

    public var body: some View {
        InlinePicker(label: "model", value: selection, valueLabel: selection.rawValue) {
            ForEach(ClaudeModel.allCases, id: \.self) { model in
                Button {
                    selection = model
                    onChange(model)
                } label: {
                    VStack(alignment: .leading) {
                        Text(model.displayName)
                        Text(model.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

public struct ModePicker: View {
    @Binding public var selection: PermissionMode
    public var onChange: (PermissionMode) -> Void

    public init(selection: Binding<PermissionMode>, onChange: @escaping (PermissionMode) -> Void = { _ in }) {
        self._selection = selection
        self.onChange = onChange
    }

    public var body: some View {
        InlinePicker(label: "mode", value: selection, valueLabel: selection.rawValue) {
            ForEach(PermissionMode.allCases, id: \.self) { mode in
                Button {
                    selection = mode
                    onChange(mode)
                } label: {
                    VStack(alignment: .leading) {
                        Text(mode.displayName)
                        Text(mode.shortDescription).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

public struct EffortPicker: View {
    @Binding public var selection: EffortLevel
    public var onChange: (EffortLevel) -> Void

    public init(selection: Binding<EffortLevel>, onChange: @escaping (EffortLevel) -> Void = { _ in }) {
        self._selection = selection
        self.onChange = onChange
    }

    public var body: some View {
        InlinePicker(label: "effort", value: selection, valueLabel: selection.rawValue) {
            ForEach(EffortLevel.allCases, id: \.self) { level in
                Button {
                    selection = level
                    onChange(level)
                } label: {
                    VStack(alignment: .leading) {
                        Text(level.displayName)
                        Text(level.shortDescription).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
