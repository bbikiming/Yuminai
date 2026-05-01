import SwiftUI
import AppKit
import SwiftTerm

/// SwiftTerm 기반 임베드 터미널 패널 (ADR-027 phase A1).
///
/// macOS native PTY + ANSI escape 처리. SwiftTerm의 LocalProcessTerminalView를
/// SwiftUI에 wrap. 워크스페이스 디렉토리에서 zsh를 spawn해서 사용자가 즉시
/// build/test/git 등 실행 가능.
///
/// **lock-in 완화**: 외부 코드는 SwiftTerm을 직접 import하지 않고 이 view만 사용.
public struct TerminalPane: NSViewRepresentable {
    public let workingDirectory: String
    public let onCommandFinished: ((Int32) -> Void)?

    public init(
        workingDirectory: String,
        onCommandFinished: ((Int32) -> Void)? = nil
    ) {
        self.workingDirectory = workingDirectory
        self.onCommandFinished = onCommandFinished
    }

    public func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminal = LocalProcessTerminalView(frame: .zero)
        terminal.processDelegate = context.coordinator

        // 폰트 — Yuminai monospace 토큰과 동일한 사이즈
        terminal.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        // SwiftTerm 색상 — 기본 ANSI 16색 + ANSI 256색 자동 처리
        // 배경/전경은 NSAppearance를 따라가도록 system 색 사용
        terminal.nativeBackgroundColor = NSColor(named: "TerminalBackground") ?? NSColor.textBackgroundColor
        terminal.nativeForegroundColor = NSColor.textColor

        // shell 시작
        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shellArgs: [String] = ["--login"]
        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        // shell이 워크스페이스 디렉토리에서 시작되도록
        env.append("PWD=\(workingDirectory)")
        terminal.startProcess(
            executable: shellPath,
            args: shellArgs,
            environment: env,
            execName: nil
        )

        // 시작 직후 cd to workingDirectory (env PWD만으로는 보장 안 됨)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let cdCommand = "cd \(escapeShellPath(workingDirectory))\rclear\r"
            if let data = cdCommand.data(using: .utf8) {
                terminal.send(data: ArraySlice(data))
            }
        }

        return terminal
    }

    public func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // workingDirectory 변경 시 cd
        if context.coordinator.lastWorkingDirectory != workingDirectory {
            let cdCommand = "cd \(escapeShellPath(workingDirectory))\r"
            if let data = cdCommand.data(using: .utf8) {
                nsView.send(data: ArraySlice(data))
            }
            context.coordinator.lastWorkingDirectory = workingDirectory
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(
            workingDirectory: workingDirectory,
            onCommandFinished: onCommandFinished
        )
    }

    public final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        var lastWorkingDirectory: String
        let onCommandFinished: ((Int32) -> Void)?

        init(workingDirectory: String, onCommandFinished: ((Int32) -> Void)?) {
            self.lastWorkingDirectory = workingDirectory
            self.onCommandFinished = onCommandFinished
        }

        public func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

        public func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

        public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        public func processTerminated(source: TerminalView, exitCode: Int32?) {
            if let code = exitCode {
                onCommandFinished?(code)
            }
        }
    }

    private func escapeShellPath(_ path: String) -> String {
        // 공백·특수문자 안전 처리 — single quote escape
        let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}
