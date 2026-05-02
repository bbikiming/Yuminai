import SwiftUI
import AppKit
import SwiftTerm
import YuminaiCore

/// SwiftTerm 기반 임베드 터미널 패널 (ADR-027 phase A1, ADR-041 T10 활동 감지).
///
/// macOS native PTY + ANSI escape 처리. SwiftTerm의 LocalProcessTerminalView를
/// SwiftUI에 wrap. 워크스페이스 디렉토리에서 zsh를 spawn해서 사용자가 즉시
/// build/test/git 등 실행 가능.
///
/// **활동 감지 (ADR-041 T10)**:
/// - PTY 데이터 도착 (subclass `dataReceived` override) → `.running`
/// - 휴지 1.2초 → `.completedRecently` (체크 표시) → 추가 1.5초 → `.idle`
/// - OSC 133 semantic prompts는 zsh 기본 미지원 → 휴리스틱 우선
///
/// **lock-in 완화**: 외부 코드는 SwiftTerm을 직접 import하지 않고 이 view만 사용.
public struct TerminalPane: NSViewRepresentable {
    public let workingDirectory: String
    public let onCommandFinished: ((Int32) -> Void)?
    /// PTY 활동 변화 콜백 (ADR-041 T10) — main thread.
    public let onActivityChanged: ((TerminalSession.Activity) -> Void)?

    public init(
        workingDirectory: String,
        onCommandFinished: ((Int32) -> Void)? = nil,
        onActivityChanged: ((TerminalSession.Activity) -> Void)? = nil
    ) {
        self.workingDirectory = workingDirectory
        self.onCommandFinished = onCommandFinished
        self.onActivityChanged = onActivityChanged
    }

    public func makeNSView(context: Context) -> ActivityAwareTerminalView {
        let terminal = ActivityAwareTerminalView(frame: .zero)
        terminal.processDelegate = context.coordinator
        terminal.onActivityChanged = { [weak coord = context.coordinator] activity in
            coord?.emitActivity(activity)
        }

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

    public func updateNSView(_ nsView: ActivityAwareTerminalView, context: Context) {
        // workingDirectory 변경 시 cd
        if context.coordinator.lastWorkingDirectory != workingDirectory {
            let cdCommand = "cd \(escapeShellPath(workingDirectory))\r"
            if let data = cdCommand.data(using: .utf8) {
                nsView.send(data: ArraySlice(data))
            }
            context.coordinator.lastWorkingDirectory = workingDirectory
        }
        // 활동 callback 갱신 (Coordinator는 한 번만 만들어지므로 안전)
        context.coordinator.onActivityChanged = onActivityChanged
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(
            workingDirectory: workingDirectory,
            onCommandFinished: onCommandFinished,
            onActivityChanged: onActivityChanged
        )
    }

    public final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        var lastWorkingDirectory: String
        let onCommandFinished: ((Int32) -> Void)?
        var onActivityChanged: ((TerminalSession.Activity) -> Void)?

        init(
            workingDirectory: String,
            onCommandFinished: ((Int32) -> Void)?,
            onActivityChanged: ((TerminalSession.Activity) -> Void)?
        ) {
            self.lastWorkingDirectory = workingDirectory
            self.onCommandFinished = onCommandFinished
            self.onActivityChanged = onActivityChanged
        }

        func emitActivity(_ activity: TerminalSession.Activity) {
            // ActivityAwareTerminalView가 main에서 호출 — 그대로 전달
            onActivityChanged?(activity)
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

/// `LocalProcessTerminalView` subclass — `dataReceived` override로 PTY 출력 흐름 감지.
///
/// **휴리스틱**: 데이터 도착 시 → `.running`. 1.2초 휴지 → `.completedRecently`,
/// 추가 1.5초 후 → `.idle`. 조용한 명령 (echo 한 줄) 도 스파이크로 감지됨.
///
/// **동시성**: NSView 기반 — `dataReceived`는 SwiftTerm이 main thread에서 호출.
/// `@unchecked Sendable` (NSView 자체가 main-thread bound) + 모든 state mutation은 `assumeIsolated` MainActor.
public final class ActivityAwareTerminalView: LocalProcessTerminalView, @unchecked Sendable {
    public var onActivityChanged: ((TerminalSession.Activity) -> Void)?

    private var idleTimer: Timer?
    private var completionTimer: Timer?
    private var currentActivity: TerminalSession.Activity = .idle

    public override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        // SwiftTerm은 main에서 호출하지만 안전하게 hop
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.markRunning()
            }
        }
    }

    @MainActor
    private func markRunning() {
        if currentActivity != .running {
            currentActivity = .running
            onActivityChanged?(.running)
        }
        // 기존 타이머 reset — 추가 데이터로 idle 진입 연기
        idleTimer?.invalidate()
        completionTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.markCompletedRecently() }
            }
        }
    }

    @MainActor
    private func markCompletedRecently() {
        currentActivity = .completedRecently
        onActivityChanged?(.completedRecently)
        completionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.markIdle() }
            }
        }
    }

    @MainActor
    private func markIdle() {
        currentActivity = .idle
        onActivityChanged?(.idle)
    }
}
