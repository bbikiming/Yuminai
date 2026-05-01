import Foundation

/// 시간 의존 코드를 테스트 가능하게 만드는 추상화.
///
/// 프로덕션은 `SystemClock`, 테스트는 `FrozenClock` 또는 임의 구현.
public protocol YuminaiClock: Sendable {
    func now() -> Date
}

public struct SystemClock: YuminaiClock {
    public init() {}
    public func now() -> Date { Date() }
}
