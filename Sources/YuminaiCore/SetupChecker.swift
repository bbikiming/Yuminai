import Foundation

/// **ADR-104 / ADR-105** — 도구 설치 여부를 비동기로 검사하는 actor.
///
/// 검사 순서:
/// 1. **detectionPaths** (fast path) — 알려진 절대 경로를 FileManager로 빠르게 검사.
/// 2. **PATH 검색** (fallback) — login shell (`/bin/zsh -lc`)로 `command -v` 실행해
///    사용자의 .zshrc/.zprofile에 추가된 PATH까지 포함하여 검색.
///
/// 사용자가 비표준 위치(`~/.local/bin`, npm global, asdf 등)에 설치한 경우에도
/// 정확히 감지하기 위해 fallback이 필수.
public actor SetupChecker {

    // MARK: - InstallStatus

    /// 도구 설치 상태.
    public enum InstallStatus: Sendable, Equatable {
        /// 실행 가능한 바이너리를 발견한 경로.
        case installed(path: String)
        /// 모든 detectionPaths + PATH 검색에서 찾지 못함.
        case notInstalled
        /// 검사가 아직 실행되지 않은 초기 상태.
        case unknown
    }

    // MARK: - Init

    public init() {}

    // MARK: - Public API

    /// 단일 도구의 설치 상태를 반환. fast path → fallback 순서.
    public func check(_ tool: SetupTool) async -> InstallStatus {
        // 1. Fast path — 알려진 절대 경로 우선 검사
        if let path = await checkDetectionPaths(tool) {
            return .installed(path: path)
        }
        // 2. Fallback — login shell PATH 검색
        if let path = await whichInLoginShell(tool.executableName) {
            return .installed(path: path)
        }
        return .notInstalled
    }

    /// 모든 SetupTool을 동시에 검사해 딕셔너리로 반환.
    public func checkAll() async -> [SetupTool: InstallStatus] {
        var result: [SetupTool: InstallStatus] = [:]
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

    // MARK: - Private

    /// detectionPaths 순회 — `$HOME` 치환 + 파일 존재 + 실행 권한 검사.
    private func checkDetectionPaths(_ tool: SetupTool) async -> String? {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        let fm = FileManager.default

        for rawPath in tool.detectionPaths {
            let expanded = rawPath.replacingOccurrences(of: "$HOME", with: home)
            guard fm.fileExists(atPath: expanded) else { continue }
            guard fm.isExecutableFile(atPath: expanded) else { continue }
            return expanded
        }
        return nil
    }

    /// **Login shell PATH 검색** — `/bin/zsh -lc "command -v <name>"`.
    ///
    /// 왜 login shell인가? Yuminai는 LaunchServices로 실행되므로 PATH가
    /// `/usr/bin:/bin:/usr/sbin:/sbin`만 갖는다. 사용자의 .zprofile/.zshrc에서
    /// PATH에 추가한 `~/.local/bin`, Homebrew, npm global 등은 빠진다.
    /// `-l` (login) + `-c` (command)로 사용자 shell을 전체 source한 뒤 검색.
    private func whichInLoginShell(_ executableName: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Self.runWhich(executableName)
                continuation.resume(returning: result)
            }
        }
    }

    /// `command -v`를 zsh login shell에서 실행. 여러 후보 shell을 순차 시도.
    private static func runWhich(_ executableName: String) -> String? {
        // 사용자 기본 shell + fallback (zsh → bash) 순서
        let shellPaths = ["/bin/zsh", "/bin/bash", "/bin/sh"]

        for shellPath in shellPaths {
            guard FileManager.default.isExecutableFile(atPath: shellPath) else { continue }
            if let path = invokeShell(shellPath, command: "command -v \(executableName)") {
                return path
            }
        }
        return nil
    }

    /// 단일 shell 호출 — login + command 모드.
    private static func invokeShell(_ shellPath: String, command: String) -> String? {
        let process = Process()
        process.launchPath = shellPath
        process.arguments = ["-lc", command]
        // 환경 변수 명시적 전달 (HOME 누락 방지)
        var env = ProcessInfo.processInfo.environment
        if env["HOME"] == nil {
            env["HOME"] = NSHomeDirectory()
        }
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // command -v는 alias / function도 반환할 수 있으므로 첫 줄만 + 절대 경로 검증
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
        guard firstLine.hasPrefix("/") else { return nil }
        guard FileManager.default.isExecutableFile(atPath: firstLine) else { return nil }
        return firstLine
    }
}
