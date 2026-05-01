import Foundation

/// `claude` CLI를 자식 프로세스로 spawn할 때 사용할 환경변수를 구성한다.
///
/// GUI 앱은 `~/.zshrc`를 읽지 않으므로 PATH에 Homebrew/local/bin 등을 직접 더한다.
/// 자세한 배경은 `rules/40_PROCESS_SPAWNING.md` 참조.
public enum ProcessEnvironment {
    public static func augmented(
        base: [String: String] = ProcessInfo.processInfo.environment,
        harnessURL: URL? = nil
    ) -> [String: String] {
        var env = base

        let pathExtras = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            NSString(string: "~/.local/bin").expandingTildeInPath,
            NSString(string: "~/.cargo/bin").expandingTildeInPath
        ]
        let currentPath = env["PATH", default: ""]
            .split(separator: ":")
            .map(String.init)

        var seen = Set<String>()
        var merged: [String] = []
        for path in pathExtras + currentPath where seen.insert(path).inserted {
            merged.append(path)
        }
        env["PATH"] = merged.joined(separator: ":")

        if env["HOME"] == nil {
            env["HOME"] = NSHomeDirectory()
        }

        // PTY 사용 시 ANSI 256 색 안내
        env["TERM"] = "xterm-256color"

        // Claude CLI 하네스 위치 알리기 — 정확한 환경변수 이름은 W1 Spike에서 확인 후 갱신
        if let harnessURL {
            env["CLAUDE_CONFIG_DIR"] = harnessURL.path
        }

        return env
    }
}
