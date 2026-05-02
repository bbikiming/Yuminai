import Foundation
import Observation
import YuminaiCore

/// Delivery loop 결과 + 자동 fix feedback 상태 (ADR-042 R3.5).
///
/// **분리 근거**: state 4개 + 결과 cap/feedback 로직 응집. CheckpointManager는 별개 (AppModel 잔존).
/// triggerAutoDelivery / runDeliveryOnDemand 같은 트리거 로직은 AppModel facade가 책임 (workspace 의존).
///
/// **Facade 패턴**: AppModel은 `delivery` 보유.
@MainActor
@Observable
public final class DeliveryCoordinator {
    public var results: [DeliveryResult] = []
    public var isRunning: Bool = false
    /// 다음 turn에 사용자 prompt 앞에 prepend할 실패 컨텍스트 (auto-fix loop).
    public var pendingFailureFeedback: String = ""

    public init() {}

    /// 결과 누적 + cap (AppLimits.maxDeliveryResults).
    public func appendResults(_ newResults: [DeliveryResult]) {
        results.append(contentsOf: newResults)
        if results.count > AppLimits.maxDeliveryResults {
            results.removeFirst(results.count - AppLimits.maxDeliveryResults)
        }
    }

    public func appendResult(_ result: DeliveryResult) {
        appendResults([result])
    }

    public func clear() {
        results = []
    }

    /// 첫 실패 (build < test < lint 우선순위) — auto-fix prompt 생성 시 caller가 사용.
    public var firstFailure: DeliveryResult? {
        results.last(where: { !$0.success })
    }

    /// pendingFailureFeedback 소비 후 클리어 (sendMessage가 호출).
    public func consumePendingFailure() -> String {
        defer { pendingFailureFeedback = "" }
        return pendingFailureFeedback
    }
}
