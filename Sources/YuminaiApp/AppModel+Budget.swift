import Foundation
import AppKit
import os
import YuminaiCore
import YuminaiTelegram

// ADR-127 — AppModel.swift 분할: Budget + Cost + Routing Learning 도메인
// 이 함수들은 이동되지 않은 본체 코드(handle, consumeStream 등)에서 호출되므로 별도 extension으로 분리
extension AppModel {

    // MARK: - ADR-057 Critical Fix 1 — ChildProcess 호출용 effective settings

    /// **ADR-057 Critical Fix 1** — ChildProcess 호출용 effective settings.
    /// 외부 turn (isExternalTurn) + telegramRemoteRequiresPlan이면 plan-mode 적용.
    /// 그렇지 않으면 active settings 사용.
    /// → 외부 사용자가 /decompose /rehearse 보낼 때 plan-mode 우회 차단 (보안 hole 수정).
    public func effectiveChildSettings() -> SessionSettings {
        var settings = activeSettings
        if isExternalTurn && preferences.telegramRemoteRequiresPlan && settings.permissionMode != .plan {
            settings.permissionMode = .plan
        }
        return settings
    }

    // MARK: - ADR-056 Phase 5 — Routing learning UI helpers

    public func unmuteKeyword(_ keyword: String) async {
        await routingLearningStore.setMuted(keyword, muted: false)
        routingLearningSnapshot = await routingLearningStore.snapshot()
    }

    public func addCustomRoutingKeyword(_ keyword: String, taskKind: String) async {
        await routingLearningStore.addCustomKeyword(keyword, for: taskKind)
        routingLearningSnapshot = await routingLearningStore.snapshot()
    }

    public func removeCustomRoutingKeyword(_ keyword: String, taskKind: String) async {
        await routingLearningStore.removeCustomKeyword(keyword, for: taskKind)
        routingLearningSnapshot = await routingLearningStore.snapshot()
    }

    // MARK: - ADR-056/059/060 — Daily cost 누적 + disk persist

    /// **ADR-056 Phase 4** — daily cost 누적. 날짜 바뀌면 reset.
    /// **ADR-059 Phase 5** — workspace별 cost도 누적 (selectedWorkspaceId 기준).
    /// **ADR-060 Phase 1** — disk store에도 누적 (앱 재시작 보존).
    public func accumulateDailyCost(_ cost: Double) {
        let cal = Calendar.current
        if !cal.isDate(todayCostDate, inSameDayAs: Date()) {
            // 새 날짜 — global + workspace 모두 reset
            todayCostUSD = 0
            workspaceTodayCostUSD.removeAll()
            todayCostDate = Date()
        }
        todayCostUSD += cost
        // ADR-059 Phase 5 + ADR-060 Phase 1 — workspace별 누적 + disk persist
        if let wsId = selectedWorkspaceId {
            workspaceTodayCostUSD[wsId, default: 0.0] += cost
            // disk persist (background)
            let store = dailyCostStore
            Task { await store.addCost(workspaceId: wsId, usd: cost) }
        }
    }

    /// **ADR-060 Phase 1** — bootstrap에서 disk store cost 복원 (앱 재시작 후에도 budget 유지).
    /// **ADR-061 Phase 1** — cacheTrend snapshot도 캐싱 (UI binding).
    public func loadPersistedDailyCosts() async {
        let snap = await dailyCostStore.snapshot()
        let cal = Calendar.current
        for (wsId, ws) in snap.workspaceCosts {
            if cal.isDate(ws.date, inSameDayAs: Date()) {
                workspaceTodayCostUSD[wsId] = ws.costUSD
            }
        }
        cacheTrendSnapshot = snap.cacheTrend
    }

    /// **ADR-061 Phase 1** — cache trend snapshot 갱신 (Charts dashboard 열기 직전).
    public func refreshCacheTrendSnapshot() async {
        let snap = await dailyCostStore.snapshot()
        cacheTrendSnapshot = snap.cacheTrend
    }

    /// **ADR-056 Phase 4 + ADR-059 Phase 5** — budget cap 도달 여부.
    /// workspace별 cap이 있으면 그것 우선, 없으면 global dailyBudgetUSD.
    public func isDailyBudgetExhausted() -> Bool {
        // ADR-059 Phase 5 — workspace별 cap 우선
        if let wsId = selectedWorkspaceId,
           let wsCap = preferences.workspaceDailyBudgetsUSD[wsId] {
            let wsCost = workspaceTodayCostUSD[wsId] ?? 0
            if wsCost >= wsCap { return true }
        }
        // global cap fallback
        guard let cap = preferences.dailyBudgetUSD else { return false }
        return todayCostUSD >= cap
    }

    /// **ADR-057 Critical Fix 4** — atomic check + reserve (race 방지).
    /// 외부 turn 시작 시 호출 → 동시 turn 2개가 둘 다 cap check 통과하는 race 차단.
    /// reserve를 미리 추가 (estimated min cost) → 두 번째 turn은 reserve 포함 합계로 cap check.
    /// turn 종료 시 actual cost로 보정 (reserve 차감 + actual 추가).
    /// **MainActor 보장** — 동시 호출 시에도 직렬화됨 (struct flag 단순 + atomic).
    public func tryReserveDailyBudget(estimatedMinCostUSD: Double = 0.001) -> Bool {
        guard preferences.dailyBudgetUSD != nil else { return true }  // cap 없으면 통과
        // ADR-058 Phase 6 — 자정 reset push (lazy check)
        maybeBudgetResetPush()
        // 날짜 reset check
        let cal = Calendar.current
        if !cal.isDate(todayCostDate, inSameDayAs: Date()) {
            todayCostUSD = 0
            todayCostDate = Date()
        }
        // 이미 cap 도달
        if isDailyBudgetExhausted() { return false }
        // reserve를 미리 추가 (race 방지) — 동시 turn 2개면 두 번째는 누적된 reserve 포함 합계로 check
        accumulateDailyCost(estimatedMinCostUSD)
        return !isDailyBudgetExhausted()
    }

    // MARK: - ADR-056 Phase 3 — Context warning + auto new session

    /// **ADR-056 Phase 3** — 컨텍스트 70%+ 시 Telegram 자동 push (하루 1회).
    /// **ADR-058 Phase 5** — autoNewSessionContextThreshold 도달 시 자동 새 세션 옵션.
    /// completed 이벤트 후 호출.
    public func maybeAutoPushContextWarning() {
        let pct = currentContextUsage
        // ADR-058 Phase 5 — 자동 새 세션 (사용자 명시 활성 시만)
        if let autoThresh = preferences.autoNewSessionContextThreshold, pct >= autoThresh {
            harness.appendSystem("🔄 자동 새 세션 시작 — 컨텍스트 \(Int(pct * 100))% ≥ \(Int(autoThresh * 100))% (Settings에서 비활성 가능)")
            // 사용자에게 알림 + 새 session spawn (active pane 재spawn)
            if let bridge = sessionBridge {
                let msg = "🔄 컨텍스트 \(Int(pct * 100))% — 자동으로 새 세션 시작합니다."
                Task { await bridge.sendNotice(msg) }
            }
            // active pane session 재시작 (현재 messages는 새 session으로 안 가져감 — clean start)
            Task { @MainActor in
                if let paneId = self.activePaneId {
                    await self.setActivePane(paneId)  // re-spawn
                }
            }
            return
        }
        // 70% 일반 push (하루 1회)
        guard pct >= 0.70 else { return }
        let cal = Calendar.current
        if let last = lastContextWarnDate, cal.isDate(last, inSameDayAs: Date()) {
            return
        }
        guard let bridge = sessionBridge else { return }
        let pctInt = Int(pct * 100)
        let model = activeSettings.model.displayName
        let msg = "⚠ 컨텍스트 \(pctInt)% (\(model)) — 새 세션 시작 권장.\n• PC에서 새 세션 만들기\n• Settings에서 '자동 새 세션' 옵션 활성 가능 (ADR-058)"
        Task { await bridge.sendNotice(msg) }
        lastContextWarnDate = Date()
    }

    /// **ADR-058 Phase 6** — 자정 reset push.
    /// 어제 budget cap 도달 → 오늘 reset 됐으면 사용자에게 알림.
    /// turn 시작 시 호출 (lazy check).
    public func maybeBudgetResetPush() {
        guard preferences.dailyBudgetUSD != nil else { return }
        let cal = Calendar.current
        // 오늘 이미 push 했으면 skip
        if let last = lastBudgetResetPushDate, cal.isDate(last, inSameDayAs: Date()) {
            return
        }
        // todayCostDate가 어제 이전 + 어제 cap 도달했었으면 push
        // 단순화: todayCostDate가 어제 이전이면 무조건 reset 안내 (cap 도달 여부 무관)
        if !cal.isDate(todayCostDate, inSameDayAs: Date()) {
            // reset 발생 — push
            if let bridge = sessionBridge {
                let cap = preferences.dailyBudgetUSD ?? 0
                let msg = "🌅 오늘 budget reset 됐어요. cap: $\(String(format: "%.4f", cap))/일. 외부 turn 가능."
                Task { await bridge.sendNotice(msg) }
            }
            lastBudgetResetPushDate = Date()
        }
    }
}
