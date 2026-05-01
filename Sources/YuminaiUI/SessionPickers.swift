import SwiftUI
import YuminaiCore

/// 모델/모드/효과 picker — Composer footer 또는 toolbar에서 사용.
struct InlinePicker: View {
    let label: String
    let valueLabel: String
    let menu: () -> AnyView

    init(
        label: String,
        valueLabel: String,
        @ViewBuilder menu: @escaping () -> some View
    ) {
        self.label = label
        self.valueLabel = valueLabel
        self.menu = { AnyView(menu()) }
    }

    @State private var hovering = false

    var body: some View {
        Menu {
            menu()
        } label: {
            HStack(spacing: 5) {
                Text(label)
                    .foregroundStyle(Theme.Color.textTertiary)
                Text("·")
                    .foregroundStyle(Theme.Color.textTertiary)
                Text(valueLabel)
                    .foregroundStyle(Theme.Color.text)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Theme.Color.textTertiary)
                    .padding(.leading, 1)
            }
            .font(Theme.Typography.label)
            .padding(.horizontal, Theme.Spacing.md - 2)
            .padding(.vertical, Theme.Spacing.xs + 1)
            .background(hovering ? Theme.Color.surfaceHi : .clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
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
        InlinePicker(label: "model", valueLabel: selection.rawValue) {
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
        InlinePicker(label: "mode", valueLabel: selection.rawValue) {
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
        InlinePicker(label: "effort", valueLabel: selection.rawValue) {
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
