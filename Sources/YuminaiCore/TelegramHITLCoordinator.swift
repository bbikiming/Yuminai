import Foundation

/// **ADR-094 Phase 3** — HITL (Human-In-The-Loop) 승인 조율 actor.
///
/// 위험한 작업 실행 전 데스크탑 UI 및 Telegram inline button을 통해
/// 사용자 승인을 요청하고 결과를 기다린다.
///
/// ## 상태 머신
/// 1. `request(...)` → 새 Request 생성 + Continuation 등록 + AsyncStream emit + timeout Task 시작 → await
/// 2. `respond(...)` → 해당 Continuation resume + 등록 제거
/// 3. timeout → 자동 `.timeout` resume + 등록 제거
/// 4. `cancel(...)` → 해당 Continuation resume(.cancelled) + 등록 제거
///
/// 다중 request 동시 지원 (id 기반 lookup).
public actor TelegramHITLCoordinator {

    // MARK: - Types

    /// HITL 요청에 대한 응답.
    public enum HITLResponse: Sendable, Equatable {
        case approved(by: String)
        case rejected(by: String)
        case timeout
        case cancelled
    }

    /// 단일 HITL 요청 descriptor.
    public struct Request: Sendable, Equatable, Identifiable {
        public let id: UUID
        /// 실행하려는 작업 설명 (예: "git push --force origin main").
        public let action: String
        /// 관련 workspace 이름 (nil이면 미연결).
        public let workspace: String?
        /// diff 미리보기 텍스트 (nil이면 없음).
        public let diffPreview: String?
        public let createdAt: Date
        /// timeout 초 수.
        public let timeoutSeconds: Int
    }

    // MARK: - Private state

    private struct PendingEntry {
        let request: Request
        let continuation: CheckedContinuation<HITLResponse, Never>
    }

    private var pending: [UUID: PendingEntry] = [:]
    private var streamContinuation: AsyncStream<Request>.Continuation?

    // MARK: - Public interface

    public init() {}

    /// 새 HITL 요청을 등록하고 응답이 올 때까지 suspend한다.
    /// timeout 초 후 `.timeout`으로 자동 resume.
    @discardableResult
    public func request(
        action: String,
        workspace: String?,
        diffPreview: String?,
        timeout timeoutSeconds: Int = 60
    ) async -> HITLResponse {
        let req = Request(
            id: UUID(),
            action: action,
            workspace: workspace,
            diffPreview: diffPreview,
            createdAt: Date(),
            timeoutSeconds: timeoutSeconds
        )

        // AsyncStream에 새 request 알림
        streamContinuation?.yield(req)

        return await withCheckedContinuation { (cont: CheckedContinuation<HITLResponse, Never>) in
            pending[req.id] = PendingEntry(request: req, continuation: cont)

            // timeout Task
            Task { [weak self, reqId = req.id] in
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                await self?.timeoutIfPending(id: reqId)
            }
        }
    }

    /// 외부에서 응답 주입 (데스크탑 UI 또는 Telegram callback에서 호출).
    public func respond(id: UUID, response: HITLResponse) {
        guard let entry = pending.removeValue(forKey: id) else { return }
        entry.continuation.resume(returning: response)
    }

    /// 활성 pending request 목록 반환 (UI 표시용).
    public func pendingRequests() -> [Request] {
        pending.values.map(\.request).sorted { $0.createdAt < $1.createdAt }
    }

    /// 특정 request를 `.cancelled`로 resolve.
    public func cancel(id: UUID) {
        guard let entry = pending.removeValue(forKey: id) else { return }
        entry.continuation.resume(returning: .cancelled)
    }

    /// 새 request 생성 시 push되는 AsyncStream.
    /// UI (HITLApprovalSheet)와 Telegram message sender가 구독.
    public func requestStream() -> AsyncStream<Request> {
        AsyncStream { cont in
            self.streamContinuation = cont
        }
    }

    // MARK: - Private

    private func timeoutIfPending(id: UUID) {
        guard let entry = pending.removeValue(forKey: id) else { return }
        entry.continuation.resume(returning: .timeout)
    }
}
