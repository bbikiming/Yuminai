import SwiftUI
import YuminaiCore

/// 채팅 영역 상단 toolbar. 좌측 워크스페이스 메타, 가운데 picker, 우측 액션.
public struct ChatToolbar: View {
    public let workspaceName: String
    @Binding public var model: ClaudeModel
    @Binding public var permissionMode: PermissionMode
    @Binding public var effortLevel: EffortLevel
    public let isStreaming: Bool
    public let inspectorVisible: Bool
    public let onSettingsApply: (SessionSettings) -> Void
    public let onToggleInspector: () -> Void
    public let onShowDashboard: () -> Void
    public let onToggleSidebar: () -> Void

    public init(
        workspaceName: String,
        model: Binding<ClaudeModel>,
        permissionMode: Binding<PermissionMode>,
        effortLevel: Binding<EffortLevel>,
        isStreaming: Bool,
        inspectorVisible: Bool,
        onSettingsApply: @escaping (SessionSettings) -> Void,
        onToggleInspector: @escaping () -> Void,
        onShowDashboard: @escaping () -> Void,
        onToggleSidebar: @escaping () -> Void = {}
    ) {
        self.workspaceName = workspaceName
        self._model = model
        self._permissionMode = permissionMode
        self._effortLevel = effortLevel
        self.isStreaming = isStreaming
        self.inspectorVisible = inspectorVisible
        self.onSettingsApply = onSettingsApply
        self.onToggleInspector = onToggleInspector
        self.onShowDashboard = onShowDashboard
        self.onToggleSidebar = onToggleSidebar
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            FlatButton("", icon: "sidebar.left", variant: .ghost, size: .small, action: onToggleSidebar)
                .help("사이드바 (⌘⌥1)")

            HStack(spacing: Theme.Spacing.xs) {
                Text("[")
                    .foregroundStyle(Theme.Color.textTertiary)
                Text(workspaceName)
                    .foregroundStyle(Theme.Color.text)
                Text("]")
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            .font(Theme.Typography.label)

            FlatVDivider().frame(height: 14)

            ModelPicker(selection: $model) { _ in apply() }
            ModePicker(selection: $permissionMode) { _ in apply() }
            EffortPicker(selection: $effortLevel) { _ in apply() }

            if isStreaming {
                streamingBadge
            }

            Spacer()

            FlatButton("", icon: "chart.bar", variant: .ghost, size: .small, action: onShowDashboard)
                .help("사용량 (⌘D)")
                .keyboardShortcut("d", modifiers: .command)

            FlatButton("",
                       icon: inspectorVisible ? "sidebar.right.fill" : "sidebar.right",
                       variant: .ghost, size: .small, action: onToggleInspector)
                .help("Inspector (⌘⌥I)")
                .keyboardShortcut("i", modifiers: [.command, .option])
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: Theme.Layout.toolbarHeight)
        .flatChrome(borders: [.bottom])
    }

    private var streamingBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Theme.Color.accent)
                .frame(width: 6, height: 6)
            Text("streaming")
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Color.accent)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 2)
        .background(Theme.Color.accentMuted)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .stroke(Theme.Color.accentBorder, lineWidth: Theme.Stroke.hairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private func apply() {
        onSettingsApply(SessionSettings(
            model: model,
            permissionMode: permissionMode,
            effortLevel: effortLevel
        ))
    }
}
