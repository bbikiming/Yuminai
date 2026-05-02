import Foundation

/// 앱 전역 limit 상수 — magic number 추출 (ADR-043 R4).
///
/// **이전**: AppModel/CommandRunner/FileTab 등에 hard-coded `10`/`50` 산재.
/// **분리 근거**: 사용자 customize 또는 테스트 격리 시 한 곳에서 변경.
public enum AppLimits {
    /// 동시 열 수 있는 파일 탭 (FIFO non-dirty 제거).
    public static let maxFileTabs: Int = 10

    /// 워크스페이스 별 동시 터미널 세션 (ADR-043 R4 — 10→5 hard cap, 메모리/CPU 보호).
    /// 비활성 세션도 PTY process가 살아있으므로 (활동 감지 위해) 메모리 비용이 큼.
    /// 5개를 넘으면 실용적 multi-tasking이 아닌 cluttering임.
    public static let maxTerminalSessions: Int = 5

    /// CommandRunner 에서 메모리에 유지하는 block 수.
    public static let maxCommandBlocks: Int = 50

    /// DeliveryRunner에서 메모리에 유지하는 result 수.
    public static let maxDeliveryResults: Int = 10

    /// sendMessage 시 토큰 size 추정 경고 임계 (utf8 byte / 4 ≈ token).
    public static let oversizedPromptTokenThreshold: Int = 50_000
}
