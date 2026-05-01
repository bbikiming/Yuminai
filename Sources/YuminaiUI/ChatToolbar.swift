import SwiftUI
import YuminaiCore

/// 채팅 영역 상단에 항상 표시되는 toolbar. Claude Code 데스크탑 룩.
///
/// 좌측: 워크스페이스 메타 (이름)
/// 가운데: 모델/모드/효과 picker (inline)
/// 우측: 사용량 dashboard 버튼, inspector toggle
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

    public init(
        workspaceName: String,
        model: Binding<ClaudeModel>,
        permissionMode: Binding<PermissionMode>,
        effortLevel: Binding<EffortLevel>,
        isStreaming: Bool,
        inspectorVisible: Bool,
        onSettingsApply: @escaping (SessionSettings) -> Void,
        onToggleInspector: @escaping () -> Void,
        onShowDashboard: @escaping () -> Void
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
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            workspaceLabel
            Divider().frame(height: 16)
            ModelPicker(selection: $model, onChange: { _ in apply() })
            ModePicker(selection: $permissionMode, onChange: { _ in apply() })
            EffortPicker(selection: $effortLevel, onChange: { _ in apply() })

            if isStreaming {
                streamingBadge
            }

            Spacer()

            Button(action: onShowDashboard) {
                Image(systemName: "chart.bar.xaxis")
            }
            .buttonStyle(.plain)
            .help("사용량 대시보드 (⌘D)")
            .keyboardShortcut("d", modifiers: .command)

            Button(action: onToggleInspector) {
                Image(systemName: inspectorVisible ? "sidebar.right" : "sidebar.right")
                    .symbolVariant(inspectorVisible ? .fill : .none)
            }
            .buttonStyle(.plain)
            .help("Inspector 토글 (⌘⌥I)")
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .chromeBackground()
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.Color.dividerSubtle)
                .frame(height: 1)
        }
    }

    private var workspaceLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .foregroundStyle(Theme.Color.labelSecondary)
                .font(.caption)
            Text(workspaceName)
                .font(Theme.Typography.toolbarLabel)
                .foregroundStyle(Theme.Color.label)
        }
    }

    private var streamingBadge: some View {
        HStack(spacing: 4) {
            ProgressView()
                .controlSize(.mini)
            Text("스트리밍 중")
                .font(Theme.Typography.toolbarLabel)
                .foregroundStyle(Theme.Color.accent)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 3)
        .background(Theme.Color.accentMuted, in: Capsule())
    }

    private func apply() {
        onSettingsApply(SessionSettings(
            model: model,
            permissionMode: permissionMode,
            effortLevel: effortLevel
        ))
    }
}
