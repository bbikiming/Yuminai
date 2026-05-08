import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-094 Phase 3** — 데스크탑 HITL 승인 sheet.
///
/// ## 디자인 (ADR-092 §4.6)
/// - 대기 중인 request 표시 (첫 번째 + "+N more")
/// - Live timeout countdown (Timer)
/// - Approve / Reject 버튼 → `TelegramHITLCoordinator.respond(...)`
/// - 다중 요청 시 탭으로 전환
struct HITLApprovalSheet: View {
    @Environment(AppModel.self) private var appModel
    @State private var selectedIndex: Int = 0
    @State private var remainingSeconds: Int = 0
    @State private var countdownTimer: Timer? = nil

    var body: some View {
        let requests = appModel.hitlPendingRequests
        YuminaiSheet(width: 560, height: 480) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header(count: requests.count)

                if requests.isEmpty {
                    emptyState
                } else {
                    if requests.count > 1 {
                        tabPicker(requests: requests)
                    }

                    let currentIndex = min(selectedIndex, requests.count - 1)
                    if currentIndex >= 0 {
                        requestDetail(requests[currentIndex])
                    }
                }
            }
            .padding(Theme.Spacing.lg)
        } footer: {
            if !requests.isEmpty {
                let currentIndex = min(selectedIndex, requests.count - 1)
                if currentIndex >= 0 {
                    actionBar(request: requests[currentIndex])
                }
            } else {
                HStack {
                    Spacer()
                    FlatButton("닫기", variant: .primary) {
                        appModel.showHITLSheet = false
                    }
                }
            }
        }
        .onAppear { startCountdown() }
        .onDisappear { stopCountdown() }
        .onChange(of: appModel.hitlPendingRequests.count) { _, _ in
            if selectedIndex >= appModel.hitlPendingRequests.count {
                selectedIndex = max(0, appModel.hitlPendingRequests.count - 1)
            }
            startCountdown()
        }
    }

    // MARK: - Header

    private func header(count: Int) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24))
                .foregroundStyle(Theme.Color.warningStrong)

            VStack(alignment: .leading, spacing: 2) {
                Text("확인이 필요해요")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.text)
                if count > 0 {
                    Text("\(count)개 요청 대기 중")
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }
            Spacer()
        }
    }

    // MARK: - Tab picker (다중 요청)

    private func tabPicker(requests: [TelegramHITLCoordinator.Request]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(Array(requests.enumerated()), id: \.element.id) { index, req in
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            selectedIndex = index
                        }
                        startCountdown()
                    } label: {
                        Text(req.action.prefix(24) + (req.action.count > 24 ? "…" : ""))
                            .font(Theme.Typography.micro)
                            .foregroundStyle(index == selectedIndex ? Theme.Color.accent : Theme.Color.textSecondary)
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, 4)
                            .background(
                                index == selectedIndex
                                ? Theme.Color.accent.opacity(0.10)
                                : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    }
                    .buttonStyle(.plain)
                    // ADR-141 — 접근성: 전체 action명 label + 탭 선택 상태
                    .accessibilityLabel("요청 \(index + 1): \(req.action)")
                    .accessibilityAddTraits(index == selectedIndex ? [.isSelected] : [])
                }
            }
        }
    }

    // MARK: - Request detail

    private func requestDetail(_ req: TelegramHITLCoordinator.Request) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // Metadata
            metadataRow(req)

            // Action
            actionBox(req.action)

            // Diff preview
            if let diff = req.diffPreview {
                diffPreviewBox(diff)
            }

            // Timeout countdown
            timeoutBar(req)
        }
    }

    private func metadataRow(_ req: TelegramHITLCoordinator.Request) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if let ws = req.workspace {
                HStack(spacing: Theme.Spacing.xs) {
                    Text("Workspace:")
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textSecondary)
                    Text(ws)
                        .font(Theme.Typography.small.weight(.medium))
                        .foregroundStyle(Theme.Color.text)
                }
            }
            HStack(spacing: Theme.Spacing.xs) {
                Text("요청 시각:")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
                Text(req.createdAt, style: .time)
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.text)
            }
        }
    }

    private func actionBox(_ action: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("실행할 명령")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
            Text(action)
                .font(Theme.Typography.codeBlock)
                .foregroundStyle(Theme.Color.text)
                .padding(Theme.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .stroke(Theme.Color.border, lineWidth: 0.5)
                )
        }
    }

    private func diffPreviewBox(_ diff: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("변경사항 미리보기")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
            ScrollView(.vertical) {
                Text(diff)
                    .font(Theme.Typography.codeBlock)
                    .foregroundStyle(Theme.Color.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Spacing.sm)
            }
            .frame(maxHeight: 120)
            .background(Theme.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .stroke(Theme.Color.border, lineWidth: 0.5)
            )
        }
    }

    private func timeoutBar(_ req: TelegramHITLCoordinator.Request) -> some View {
        let total = req.timeoutSeconds
        let remaining = max(0, remainingSeconds)
        let fraction = total > 0 ? Double(remaining) / Double(total) : 0

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "timer")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Color.textTertiary)
                Text("Timeout: \(remaining)s 남음")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(remaining < 15 ? Theme.Color.danger : Theme.Color.textSecondary)
                    .animation(.linear(duration: 1), value: remaining)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.Color.border)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(remaining < 15 ? Theme.Color.danger : Theme.Color.accent)
                        .frame(width: geo.size.width * fraction, height: 6)
                        .animation(.linear(duration: 1), value: fraction)
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: - Action bar

    private func actionBar(request: TelegramHITLCoordinator.Request) -> some View {
        HStack {
            Spacer()
            FlatButton("거절", icon: "xmark.circle.fill", variant: .secondary) {
                respond(to: request, response: .rejected(by: "desktop"))
            }
            FlatButton("승인", icon: "checkmark.circle.fill", variant: .primary) {
                respond(to: request, response: .approved(by: "desktop"))
            }
        }
    }

    // MARK: - Empty state (ADR-140 — AnimatedEmptyState 통일)

    private var emptyState: some View {
        AnimatedEmptyState(
            icon: "checkmark.circle",
            iconTint: Theme.Color.accent,
            title: "대기 중인 요청 없음",
            message: "Claude가 승인을 기다리는 HITL 요청이 없습니다."
        )
    }

    // MARK: - Helpers

    private func respond(to request: TelegramHITLCoordinator.Request, response: TelegramHITLCoordinator.HITLResponse) {
        Task { await appModel.respondToHITL(id: request.id, response: response) }
    }

    private func startCountdown() {
        stopCountdown()
        let requests = appModel.hitlPendingRequests
        guard !requests.isEmpty else { return }
        let idx = min(selectedIndex, requests.count - 1)
        guard idx >= 0 else { return }
        let req = requests[idx]
        let elapsed = Int(Date().timeIntervalSince(req.createdAt))
        remainingSeconds = max(0, req.timeoutSeconds - elapsed)

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                if remainingSeconds > 0 {
                    remainingSeconds -= 1
                } else {
                    stopCountdown()
                }
            }
        }
    }

    private func stopCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }
}
