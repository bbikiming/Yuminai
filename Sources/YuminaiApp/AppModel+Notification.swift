import Foundation
import AppKit
import YuminaiCore
import YuminaiTelegram

// ADR-127 — AppModel.swift 분할: Notification 도메인 (알림 정책 + Quiet Hours + macOS 권한)
extension AppModel {

    // MARK: - ADR-095 Phase 4 — Multi-device 알림 정책 + Quiet Hours

    /// **ADR-095 Phase 4** — 사용자 입력 감지 (메시지 전송, UI 조작 등).
    public func recordUserInput() {
        lastInputAt = Date.now
        if deviceState == .desktopIdle {
            deviceState = .desktopActive
        }
        resetIdleTimer()
    }

    /// **ADR-095 Phase 4** — 5분 무입력 타이머 시작.
    /// **ADR-153 P0-3** — sleep/wake 시 polling 자동 중단/재개.
    public func setupDeviceStateMonitor() {
        resetIdleTimer()

        // ADR-148 — Swift 6.1 strict concurrency: NotificationCenter closure는 Sendable.
        // main actor isolated property는 Task { @MainActor }로 hop 후 접근.
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.deviceState = .desktopIdle
                await self?.pauseTelegramPollingForSleep()
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.deviceState = .desktopActive
                await self?.resumeTelegramPollingAfterWake()
                self?.resetIdleTimer()
            }
        }
    }

    /// **ADR-153 P0-3** — sleep 진입 시 polling 중단.
    /// 현재 활성 봇이 polling 중이면 stopPolling() 호출.
    func pauseTelegramPollingForSleep() async {
        guard let bot = telegramBot else { return }
        await bot.stopPolling()
        logger.info("sleep 감지 — Telegram polling 중단")
    }

    /// **ADR-153 P0-3** — wake 후 polling 재개.
    /// Telegram이 활성화된 상태면 startPolling() 호출.
    func resumeTelegramPollingAfterWake() async {
        guard let bot = telegramBot, preferences.telegramEnabled else { return }
        do {
            try await bot.startPolling()
            // wake 후 offline queue flush (sleep 중 쌓인 메시지 재전송)
            if let liveBot = bot as? LiveTelegramBot {
                await liveBot.flushOfflineQueueIfPossible()
            }
            logger.info("wake 감지 — Telegram polling 재개")
        } catch {
            logger.error("wake 후 polling 재시작 실패: \(error.localizedDescription)")
        }
    }

    func resetIdleTimer() {
        idleTimer?.cancel()
        idleTimer = Task { [weak self] in
            do {
                // 5분 = 300초
                try await Task.sleep(nanoseconds: 300_000_000_000)
                await MainActor.run {
                    guard let self, self.deviceState == .desktopActive else { return }
                    self.deviceState = .desktopIdle
                }
            } catch {
                // 취소됨 — 정상
            }
        }
    }

    /// **ADR-095 Phase 4** — Quiet hours + 디바이스 상태를 고려한 실제 전달 채널 반환.
    ///
    /// 1. notificationPolicy.channel(for:in:) 기본값 조회
    /// 2. quiet hours 범위이면 `generalAlert`, `taskCompleteSuccess` → `suppressed`로 격하
    public func currentDeliveryChannel(for kind: NotificationKind) -> DeliveryChannel {
        let baseChannel = preferences.notificationPolicy.channel(for: kind, in: deviceState)

        // Quiet hours 격하 체크
        if isInQuietHours() {
            switch kind {
            case .generalAlert, .taskCompleteSuccess:
                return .suppressed
            default:
                break
            }
        }

        return baseChannel
    }

    /// **ADR-095 Phase 4** — 현재 시각이 quiet hours 범위에 있는지 확인.
    private func isInQuietHours() -> Bool {
        guard let start = preferences.quietHoursStart,
              let end = preferences.quietHoursEnd else { return false }

        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: Date())

        if start <= end {
            // 예: 9~17시 (낮)
            return hour >= start && hour < end
        } else {
            // 예: 22~8시 (자정 걸침)
            return hour >= start || hour < end
        }
    }

    // MARK: - ADR-096 — Notification Policy 편집 메서드

    /// **ADR-096** — 알림 정책 매트릭스 업데이트 + persist.
    public func updateNotificationPolicy(_ matrix: NotificationPolicyMatrix) async {
        preferences = { var p = preferences; p.notificationPolicy = matrix; return p }()
        await savePreferences()
    }

    /// **ADR-096** — Quiet hours 업데이트 + persist.
    public func updateQuietHours(start: Int?, end: Int?) async {
        preferences = { var p = preferences; p.quietHoursStart = start; p.quietHoursEnd = end; return p }()
        await savePreferences()
    }

    /// **ADR-096** — HITL 타임아웃 업데이트 + persist.
    public func updateHITLTimeout(_ seconds: Int) async {
        preferences = { var p = preferences; p.hitlTimeoutSeconds = seconds; return p }()
        await savePreferences()
    }

    /// **ADR-096** — diff 미리보기 라인 한도 업데이트 + persist.
    public func updateDiffPreviewLineLimit(_ limit: Int) async {
        preferences = { var p = preferences; p.diffPreviewLineLimit = limit; return p }()
        await savePreferences()
    }

    /// **ADR-096** — 알림 정책 매트릭스를 default로 재설정 + persist.
    public func resetNotificationPolicyToDefault() async {
        preferences = { var p = preferences; p.notificationPolicy = .default; return p }()
        await savePreferences()
    }

    // MARK: - ADR-097 — macOS Notification Permission

    /// **ADR-097** — 앱 시작 시 macOS 알림 권한 상태 확인.
    public func setupNotificationStatusCheck() async {
        macOSNotificationStatus = await MacOSNotificationPermission.currentStatus()
    }

    /// **ADR-097** — 사용자 요청에 의한 macOS 알림 권한 요청.
    public func requestMacOSNotificationPermission() async {
        macOSNotificationStatus = await MacOSNotificationPermission.requestPermission()
    }
}
