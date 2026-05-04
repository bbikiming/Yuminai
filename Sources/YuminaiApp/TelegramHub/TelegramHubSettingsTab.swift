import SwiftUI
import AppKit
import YuminaiCore
import YuminaiUI

/// **ADR-096** — Telegram Hub 설정 탭.
///
/// 3개 섹션:
/// 1. Quiet Hours — 조용한 시간 켜기/끄기 + 시작/종료 시각
/// 2. HITL 설정 — 타임아웃 슬라이더 + diff 미리보기 라인 한도
/// 3. Notification Policy Matrix — 5 × 3 전달 채널 표
@MainActor
struct TelegramHubSettingsTab: View {
    @Environment(AppModel.self) private var appModel

    // Local state — 슬라이더/stepper 연속 입력을 throttle 없이 즉시 반영 가능하도록 로컬 보관
    @State private var quietEnabled: Bool = false
    @State private var quietStart: Int = 22
    @State private var quietEnd: Int = 8
    @State private var hitlTimeout: Int = 60
    @State private var diffLimit: Int = 30
    @State private var policyMatrix: NotificationPolicyMatrix = .default
    @State private var isApplyingReset: Bool = false
    @State private var isRequestingPermission: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                notificationPermissionSection
                quietHoursSection
                hitlSection
                policyMatrixSection
            }
            .padding(.vertical, Theme.Spacing.xs)
        }
        .onAppear {
            syncFromModel()
            Task { await appModel.setupNotificationStatusCheck() }
        }
    }

    // MARK: - macOS Notification Permission (ADR-097)

    private var notificationPermissionSection: some View {
        CardSection(style: .subtle) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionHeaderRow(
                    icon: "bell.badge.fill",
                    iconColor: .orange,
                    title: "macOS 알림 권한",
                    caption: permissionStatusLabel
                )

                HStack(spacing: Theme.Spacing.sm) {
                    permissionStatusIcon
                        .font(.system(size: 14))

                    Text(permissionStatusDescription)
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textSecondary)

                    Spacer()

                    if appModel.macOSNotificationStatus == .notDetermined
                        || appModel.macOSNotificationStatus == .denied {
                        if isRequestingPermission {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button(appModel.macOSNotificationStatus == .denied ? "Settings 열기" : "권한 요청") {
                                if appModel.macOSNotificationStatus == .denied {
                                    openNotificationSettings()
                                } else {
                                    Task {
                                        isRequestingPermission = true
                                        await appModel.requestMacOSNotificationPermission()
                                        isRequestingPermission = false
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    private var permissionStatusLabel: String {
        switch appModel.macOSNotificationStatus {
        case .notDetermined: return "아직 결정하지 않음"
        case .denied: return "거부됨"
        case .authorized: return "허용됨"
        case .provisional: return "임시 허용"
        case .ephemeral: return "임시"
        case .unavailable: return "사용 불가"
        }
    }

    private var permissionStatusDescription: String {
        switch appModel.macOSNotificationStatus {
        case .notDetermined: return "알림 권한을 요청하면 작업 완료 시 macOS 알림을 받을 수 있습니다."
        case .denied: return "알림이 거부되었습니다. 시스템 설정에서 직접 허용해 주세요."
        case .authorized: return "macOS 알림이 활성화되어 있습니다."
        case .provisional: return "임시 알림 권한이 부여되어 있습니다."
        case .ephemeral: return "앱 사용 중에만 알림이 표시됩니다."
        case .unavailable: return "이 환경에서는 알림 권한을 사용할 수 없습니다."
        }
    }

    @ViewBuilder
    private var permissionStatusIcon: some View {
        switch appModel.macOSNotificationStatus {
        case .authorized:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green)
        case .denied:
            Image(systemName: "xmark.circle.fill").foregroundStyle(Color.red)
        case .notDetermined:
            Image(systemName: "questionmark.circle").foregroundStyle(Theme.Color.textTertiary)
        case .provisional, .ephemeral:
            Image(systemName: "bell.badge").foregroundStyle(Color.orange)
        case .unavailable:
            Image(systemName: "minus.circle").foregroundStyle(Theme.Color.textTertiary)
        }
    }

    private func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Quiet Hours

    private var quietHoursSection: some View {
        CardSection(style: .subtle) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionHeaderRow(
                    icon: "moon.fill",
                    iconColor: .indigo,
                    title: "Quiet Hours",
                    caption: quietActiveLabel
                )

                Toggle("조용한 시간 활성화", isOn: $quietEnabled)
                    .font(Theme.Typography.small)
                    .onChange(of: quietEnabled) { _, newValue in
                        Task { await applyQuietHours(enabled: newValue) }
                    }

                if quietEnabled {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        HStack(spacing: Theme.Spacing.xl) {
                            hourStepper("시작", value: $quietStart) {
                                Task { await applyQuietHours(enabled: true) }
                            }
                            hourStepper("종료", value: $quietEnd) {
                                Task { await applyQuietHours(enabled: true) }
                            }
                            Spacer()
                        }
                        Text("자정을 걸치는 범위도 지원 (예: 22시 시작 ~ 08시 종료).")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.textTertiary)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                }
            }
        }
    }

    private func hourStepper(_ label: String, value: Binding<Int>, onChange: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
            Stepper(
                "\(value.wrappedValue)시",
                value: value,
                in: 0...23,
                onEditingChanged: { _ in onChange() }
            )
            .font(Theme.Typography.small)
        }
    }

    private var quietActiveLabel: String? {
        guard quietEnabled,
              let start = appModel.preferences.quietHoursStart,
              let end = appModel.preferences.quietHoursEnd else { return nil }

        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: Date())
        let isActive: Bool
        if start <= end {
            isActive = hour >= start && hour < end
        } else {
            isActive = hour >= start || hour < end
        }
        return isActive ? "현재: 활성 중" : "현재: 비활성"
    }

    // MARK: - HITL 설정

    private var hitlSection: some View {
        CardSection(style: .subtle) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionHeaderRow(
                    icon: "hand.raised.fill",
                    iconColor: Theme.Color.accent,
                    title: "HITL 설정"
                )

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("HITL 타임아웃: \(hitlTimeout)초")
                        .font(Theme.Typography.small)
                    Slider(value: Binding(
                        get: { Double(hitlTimeout) },
                        set: { hitlTimeout = Int($0) }
                    ), in: 10...300, step: 10)
                    .onChange(of: hitlTimeout) { _, newValue in
                        Task { await appModel.updateHITLTimeout(newValue) }
                    }
                    Text("Telegram에서 approve/reject 응답을 기다리는 최대 시간.")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }

                Divider()

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Diff 미리보기 라인 한도")
                        .font(Theme.Typography.small)
                    Stepper(
                        "\(diffLimit)줄",
                        value: $diffLimit,
                        in: 10...100,
                        step: 5,
                        onEditingChanged: { _ in
                            Task { await appModel.updateDiffPreviewLineLimit(diffLimit) }
                        }
                    )
                    .font(Theme.Typography.small)
                    Text("이 줄 수를 초과하는 diff는 sendDocument로 전송됩니다.")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
            }
        }
    }

    // MARK: - Notification Policy Matrix

    private var policyMatrixSection: some View {
        CardSection(style: .subtle) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack {
                    SectionHeaderRow(
                        icon: "bell.badge.fill",
                        iconColor: Theme.Color.accent,
                        title: "알림 정책 매트릭스",
                        caption: "알림 종류 × 디바이스 상태 → 전달 채널"
                    )
                    Spacer()
                    FlatButton(
                        "기본값으로 재설정",
                        icon: "arrow.counterclockwise",
                        variant: .ghost
                    ) {
                        Task { await resetMatrix() }
                    }
                    .disabled(isApplyingReset)
                }

                policyTable
            }
        }
    }

    private var policyTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            policyTableHeader
            Divider()
            ForEach(NotificationKind.allCases, id: \.self) { kind in
                policyRow(kind: kind)
                if kind != NotificationKind.allCases.last {
                    Divider()
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .stroke(Theme.Color.borderSubtle, lineWidth: 0.5)
        )
    }

    private var policyTableHeader: some View {
        HStack(spacing: 0) {
            Text("알림 종류")
                .font(Theme.Typography.micro.weight(.semibold))
                .foregroundStyle(Theme.Color.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xs)

            ForEach(DeviceState.allCases, id: \.self) { state in
                Text(state.displayLabel)
                    .font(Theme.Typography.micro.weight(.semibold))
                    .foregroundStyle(Theme.Color.textTertiary)
                    .frame(width: 100, alignment: .center)
                    .padding(.vertical, Theme.Spacing.xs)
            }
        }
        .background(Theme.Color.surfaceHi.opacity(0.5))
    }

    private func policyRow(kind: NotificationKind) -> some View {
        HStack(spacing: 0) {
            Text(kind.displayLabel)
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xs)

            ForEach(DeviceState.allCases, id: \.self) { state in
                channelPicker(kind: kind, state: state)
                    .frame(width: 100, alignment: .center)
                    .padding(.vertical, Theme.Spacing.xs)
            }
        }
    }

    private func channelPicker(kind: NotificationKind, state: DeviceState) -> some View {
        let binding = Binding<DeliveryChannel>(
            get: {
                policyMatrix.channel(for: kind, in: state)
            },
            set: { newChannel in
                var updatedRules = policyMatrix.rules
                var stateMap = updatedRules[kind] ?? [:]
                stateMap[state] = newChannel
                updatedRules[kind] = stateMap
                policyMatrix = NotificationPolicyMatrix(rules: updatedRules)
                Task { await appModel.updateNotificationPolicy(policyMatrix) }
            }
        )

        return Menu {
            ForEach(DeliveryChannel.allCases, id: \.self) { channel in
                Button {
                    binding.wrappedValue = channel
                } label: {
                    Label(channel.displayLabel, systemImage: channel.icon)
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: binding.wrappedValue.icon)
                    .font(.system(size: 10))
                Text(binding.wrappedValue.shortLabel)
                    .font(Theme.Typography.micro)
            }
            .foregroundStyle(Theme.Color.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Theme.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .stroke(Theme.Color.borderSubtle, lineWidth: 0.5)
            )
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: - Actions

    private func applyQuietHours(enabled: Bool) async {
        if enabled {
            await appModel.updateQuietHours(start: quietStart, end: quietEnd)
        } else {
            await appModel.updateQuietHours(start: nil, end: nil)
        }
    }

    private func resetMatrix() async {
        isApplyingReset = true
        policyMatrix = .default
        await appModel.resetNotificationPolicyToDefault()
        isApplyingReset = false
    }

    private func syncFromModel() {
        let prefs = appModel.preferences
        quietEnabled = prefs.quietHoursStart != nil && prefs.quietHoursEnd != nil
        quietStart = prefs.quietHoursStart ?? 22
        quietEnd = prefs.quietHoursEnd ?? 8
        hitlTimeout = prefs.hitlTimeoutSeconds
        diffLimit = prefs.diffPreviewLineLimit
        policyMatrix = prefs.notificationPolicy
    }
}

// MARK: - Display labels

extension DeviceState {
    fileprivate var displayLabel: String {
        switch self {
        case .desktopActive: return "활성"
        case .desktopIdle:   return "유휴"
        case .desktopOff:    return "오프"
        }
    }
}

extension NotificationKind {
    fileprivate var displayLabel: String {
        switch self {
        case .hitlApprovalRequest: return "HITL 승인 요청"
        case .taskCompleteSuccess: return "작업 완료 (성공)"
        case .taskCompleteFailure: return "작업 실패"
        case .rateLimitAlert:      return "Rate Limit 경고"
        case .generalAlert:        return "일반 알림"
        }
    }
}

extension DeliveryChannel {
    fileprivate var displayLabel: String {
        switch self {
        case .macOSOnly:   return "macOS만"
        case .telegramOnly: return "Telegram만"
        case .both:        return "둘 다"
        case .suppressed:  return "억제"
        }
    }

    fileprivate var shortLabel: String {
        switch self {
        case .macOSOnly:   return "macOS"
        case .telegramOnly: return "TG"
        case .both:        return "둘 다"
        case .suppressed:  return "억제"
        }
    }

    fileprivate var icon: String {
        switch self {
        case .macOSOnly:   return "desktopcomputer"
        case .telegramOnly: return "paperplane.fill"
        case .both:        return "arrow.triangle.2.circlepath"
        case .suppressed:  return "bell.slash.fill"
        }
    }
}
