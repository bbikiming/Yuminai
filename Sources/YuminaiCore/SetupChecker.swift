import Foundation

/// **ADR-104** — 도구 설치 여부를 비동기로 검사하는 actor.
///
/// detectionPaths를 순회하며 FileManager로 파일 존재 + 실행 권한을 확인.
/// `$HOME`은 `ProcessInfo.processInfo.environment["HOME"]`으로 치환.
public actor SetupChecker {

    // MARK: - InstallStatus

    /// 도구 설치 상태.
    public enum InstallStatus: Sendable, Equatable {
        /// 실행 가능한 바이너리를 발견한 경로.
        case installed(path: String)
        /// 모든 detectionPaths에서 찾지 못함.
        case notInstalled
        /// 검사가 아직 실행되지 않은 초기 상태.
        case unknown
    }

    // MARK: - Init

    public init() {}

    // MARK: - Public API

    /// 단일 도구의 설치 상태를 반환.
    public func check(_ tool: SetupTool) async -> InstallStatus {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        let fm = FileManager.default

        for rawPath in tool.detectionPaths {
            let expanded = rawPath.replacingOccurrences(of: "$HOME", with: home)
            guard fm.fileExists(atPath: expanded) else { continue }
            guard fm.isExecutableFile(atPath: expanded) else { continue }
            return .installed(path: expanded)
        }
        return .notInstalled
    }

    /// 모든 SetupTool을 동시에 검사해 딕셔너리로 반환.
    public func checkAll() async -> [SetupTool: InstallStatus] {
        var result: [SetupTool: InstallStatus] = [:]
        // actor 내부이므로 structured concurrency로 병렬 실행
        await withTaskGroup(of: (SetupTool, InstallStatus).self) { group in
            for tool in SetupTool.allCases {
                group.addTask {
                    let status = await self.check(tool)
                    return (tool, status)
                }
            }
            for await (tool, status) in group {
                result[tool] = status
            }
        }
        return result
    }
}
