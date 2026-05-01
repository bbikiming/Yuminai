import SwiftUI
import YuminaiCore

/// 모델/모드/효과 picker 공통 룩&필.
///
/// CLI 스타일 — 작은 라벨 + 현재 값 + chevron. 누르면 menu가 펼쳐짐.
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
                    .font(Theme.Typography.toolbarLabel)
                    .foregroundStyle(Theme.Color.labelTertiary)
                Text(valueLabel)
                    .font(Theme.Typography.toolbarLabel)
                    .foregroundStyle(Theme.Color.label)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(Theme.Color.labelSecondary)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Theme.Color.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
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
        InlinePicker(
            label: "model",
            value: selection,
            valueLabel: selection.displayName
        ) {
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
        InlinePicker(
            label: "mode",
            value: selection,
            valueLabel: selection.displayName
        ) {
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
        InlinePicker(
            label: "effort",
            value: selection,
            valueLabel: selection.displayName
        ) {
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
