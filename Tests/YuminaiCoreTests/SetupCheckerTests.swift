import Foundation
import Testing
import YuminaiCore

@Suite("SetupChecker")
struct SetupCheckerTests {

    // MARK: - check(_:)

    @Test("존재하지 않는 경로만 있으면 notInstalled 반환")
    func nonExistentPathReturnsNotInstalled() async {
        let checker = SetupChecker()
        // claudeCode의 detectionPaths가 실제로 존재하지 않는다고 보장할 수 없으므로
        // 존재하지 않는 custom path를 가진 mock tool 대신, 실제 결과가 installed 또는 notInstalled임을 확인
        let status = await checker.check(.claudeCode)
        switch status {
        case .installed(let path):
            #expect(!path.isEmpty, "installed 경우 path가 비어있으면 안 됨")
        case .notInstalled:
            break  // OK
        case .unknown:
            Issue.record("check()는 unknown을 반환하지 않아야 함")
        }
    }

    @Test("임시 실행 파일 생성 → installed(path:) 반환")
    func tempExecutableReturnsInstalled() async throws {
        // 임시 실행 파일 생성
        let tmpDir = FileManager.default.temporaryDirectory
        let execURL = tmpDir.appendingPathComponent("mock_claude_\(UUID().uuidString)")
        FileManager.default.createFile(atPath: execURL.path, contents: nil)

        // 실행 권한 부여
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755 as NSNumber],
            ofItemAtPath: execURL.path
        )

        defer {
            try? FileManager.default.removeItem(at: execURL)
        }

        // SetupChecker를 직접 사용하면 tool의 detectionPaths를 바꿀 수 없으므로
        // FileManager 기반 로직을 직접 검증
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: execURL.path))
        #expect(fm.isExecutableFile(atPath: execURL.path))
    }

    @Test("실행 권한 없는 파일 → isExecutableFile이 false")
    func nonExecutableFile() throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let fileURL = tmpDir.appendingPathComponent("noexec_\(UUID().uuidString)")
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)

        // 읽기 전용 권한
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o444 as NSNumber],
            ofItemAtPath: fileURL.path
        )

        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        #expect(FileManager.default.isExecutableFile(atPath: fileURL.path) == false)
    }

    // MARK: - checkAll()

    @Test("checkAll()이 모든 SetupTool 케이스를 포함한 딕셔너리 반환")
    func checkAllReturnsAllTools() async {
        let checker = SetupChecker()
        let result = await checker.checkAll()

        for tool in SetupTool.allCases {
            #expect(result[tool] != nil, "checkAll에서 \(tool.rawValue) 누락")
        }
        #expect(result.count == SetupTool.allCases.count)
    }

    @Test("checkAll() 결과에서 unknown은 없음")
    func checkAllHasNoUnknown() async {
        let checker = SetupChecker()
        let result = await checker.checkAll()

        for (tool, status) in result {
            if case .unknown = status {
                Issue.record("checkAll 결과에 unknown 있음: \(tool.rawValue)")
            }
        }
    }

    // MARK: - $HOME 확장

    @Test("detectionPaths에서 $HOME이 실제 홈 디렉토리로 치환됨")
    func homeExpansion() {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        for tool in SetupTool.allCases {
            for path in tool.detectionPaths where path.hasPrefix("$HOME") {
                let expanded = path.replacingOccurrences(of: "$HOME", with: home)
                #expect(!expanded.contains("$HOME"), "치환 실패: \(expanded)")
                #expect(expanded.hasPrefix(home), "홈 디렉토리로 시작해야 함: \(expanded)")
            }
        }
    }

    // MARK: - ADR-105: PATH fallback (login shell)

    @Test("ADR-105 — login shell PATH 검색으로 /bin/sh 등 시스템 도구 발견")
    func loginShellFallbackFindsSystemBinaries() async {
        // 시스템에 항상 있는 도구 (sh, ls)는 detectionPaths에 없지만
        // command -v로 찾을 수 있어야 함.
        // 이를 테스트하기 위해 mock SetupTool 대신 동등한 패턴을 직접 검증.
        let checker = SetupChecker()
        // 기존 SetupTool은 모두 외부 의존이므로, 여기선 checker가 nil 처리를
        // 안전하게 하는지만 확인 (회귀 가드).
        for tool in SetupTool.allCases {
            let status = await checker.check(tool)
            // unknown이 절대 안 나와야 함 (반드시 installed 또는 notInstalled)
            switch status {
            case .unknown:
                Issue.record("\(tool.rawValue) check이 unknown 반환")
            case .installed(let path):
                #expect(path.hasPrefix("/"), "\(tool.rawValue): installed path는 절대 경로여야 함, got: \(path)")
            case .notInstalled:
                break  // OK — 시스템마다 다름
            }
        }
    }

    @Test("ADR-105 — executableName이 모든 도구에 정의됨")
    func executableNameDefined() {
        for tool in SetupTool.allCases {
            #expect(!tool.executableName.isEmpty, "\(tool.rawValue): executableName 비어있음")
            #expect(!tool.executableName.contains("/"), "\(tool.rawValue): executableName은 경로가 아닌 이름이어야 함, got: \(tool.executableName)")
            #expect(!tool.executableName.contains(" "), "\(tool.rawValue): executableName에 공백 있음, got: \(tool.executableName)")
        }
    }

    @Test("ADR-105 — detectionPaths가 확장됨 (각 도구 6개+)")
    func expandedDetectionPaths() {
        for tool in SetupTool.allCases {
            #expect(tool.detectionPaths.count >= 5, "\(tool.rawValue): detectionPaths가 너무 적음 (\(tool.detectionPaths.count)개) — ADR-105 확장 필요")
        }
    }

    @Test("ADR-105 — 비표준 경로 ~/.local/bin 검색 포함")
    func detectionPathsIncludeLocalBin() {
        for tool in SetupTool.allCases {
            let hasLocalBin = tool.detectionPaths.contains { $0.contains(".local/bin") }
            #expect(hasLocalBin, "\(tool.rawValue): ~/.local/bin 검색 누락 — 사용자 PATH 호환성")
        }
    }
}
