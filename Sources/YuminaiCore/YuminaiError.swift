import Foundation

/// Yuminai 도메인 전체의 에러. 시스템 경계(Process, Keychain, FileSystem)에서 발생한
/// 인프라 에러는 반드시 이 enum으로 변환되어 상위 레이어로 전달된다.
public enum YuminaiError: Error, LocalizedError, Sendable {
    case claudeNotInstalled(path: String)
    case claudeSpawnFailed(reason: String)
    case workspaceNotFound(id: UUID)
    case workspaceAlreadyExists(name: String)
    case keychainReadFailed(status: OSStatus)
    case keychainWriteFailed(status: OSStatus)
    case ptyOpenFailed(errno: Int32)
    case sessionCorrupted(id: UUID, reason: String)
    case pathTraversalAttempted(relative: String)
    case harnessScaffoldFailed(template: HarnessTemplateName, reason: String)

    public var errorDescription: String? {
        switch self {
        case .claudeNotInstalled(let path):
            return "Claude CLI를 \(path)에서 찾을 수 없습니다. 설정에서 경로를 확인하세요."
        case .claudeSpawnFailed(let reason):
            return "Claude 실행 실패: \(reason)"
        case .workspaceNotFound(let id):
            return "워크스페이스(\(id))를 찾을 수 없습니다."
        case .workspaceAlreadyExists(let name):
            return "이미 같은 이름의 워크스페이스가 있습니다: \(name)"
        case .keychainReadFailed(let status):
            return "Keychain 읽기 실패 (status=\(status))."
        case .keychainWriteFailed(let status):
            return "Keychain 쓰기 실패 (status=\(status))."
        case .ptyOpenFailed(let errno):
            return "PTY 열기 실패 (errno=\(errno))."
        case .sessionCorrupted(let id, let reason):
            return "세션(\(id)) 데이터 손상: \(reason)"
        case .pathTraversalAttempted(let relative):
            return "허용되지 않은 경로 접근 시도: \(relative)"
        case .harnessScaffoldFailed(let template, let reason):
            return "하네스 템플릿 적용 실패(\(template.rawValue)): \(reason)"
        }
    }
}
