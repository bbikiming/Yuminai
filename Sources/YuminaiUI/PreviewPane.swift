import SwiftUI
import WebKit
import YuminaiCore

/// WKWebView 기반 임베드 preview pane (ADR-034 A4 / ADR-035 B1).
///
/// **use case**:
/// - dev server localhost (예: `http://localhost:3000`)
/// - file:// URL (예: 정적 HTML preview)
/// - 외부 docs URL (예: `https://docs.swift.org`)
///
/// **자동 감지** (ADR-035 B1): workspace의 package.json/config 파일 분석 → dev server 추천.
public struct PreviewPane: View {
    @Binding public var urlText: String
    public let onClose: () -> Void
    public let suggestions: [DevServerDetector.Suggestion]

    @State private var loadedURL: URL?
    @State private var isLoading: Bool = false

    public init(
        urlText: Binding<String>,
        onClose: @escaping () -> Void,
        suggestions: [DevServerDetector.Suggestion] = []
    ) {
        self._urlText = urlText
        self.onClose = onClose
        self.suggestions = suggestions
    }

    public var body: some View {
        VStack(spacing: 0) {
            urlBar
            if !suggestions.isEmpty && loadedURL == nil {
                suggestionStrip
            }
            FlatHDivider()
            if let url = loadedURL {
                WebViewWrapper(url: url, isLoading: $isLoading)
                    .background(Color.white)
            } else {
                emptyState
            }
        }
        .background(Theme.Color.bg)
    }

    private var suggestionStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text("감지됨:")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                ForEach(suggestions) { sug in
                    SuggestionChip(suggestion: sug) {
                        urlText = sug.url
                        loadURL()
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 4)
        }
        .background(Theme.Color.accentMuted.opacity(0.5))
    }

    private var urlBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "safari")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.Color.accent)
            Text("Preview")
                .font(Theme.Typography.small.weight(.medium))
                .foregroundStyle(Theme.Color.text)
            HelpHint(
                "내장 브라우저 패널입니다. dev server (예: http://localhost:3000)나 정적 HTML(file://...), 또는 외부 docs URL을 표시할 수 있어요. 페이지 인터랙션은 시스템 브라우저와 동일합니다.",
                title: "Preview Pane",
                placement: .bottom
            )
            TextField("URL (예: http://localhost:3000)", text: $urlText)
                .textFieldStyle(.roundedBorder)
                .font(Theme.Typography.monoSmall)
                .onSubmit { loadURL() }
            Button(action: loadURL) {
                Image(systemName: isLoading ? "arrow.triangle.2.circlepath" : "arrow.right.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Color.accent)
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .help("로드 (Return)")
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Preview 닫기")
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Color.surface)
    }

    private var emptyState: some View {
        EmptyStateHint(
            icon: "globe",
            title: "URL을 입력하세요",
            message: suggestions.isEmpty
                ? "dev server (`http://localhost:3000`)나 정적 HTML(`file:///...`)을 입력하고 Return을 누르면 표시됩니다."
                : "위에서 감지된 dev server를 클릭하거나 직접 URL을 입력하세요. 서버가 실행 중인지 먼저 확인해주세요.",
            action: nil
        )
    }

    private func loadURL() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // scheme이 없으면 http:// 자동
        let withScheme: String
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") || trimmed.hasPrefix("file://") {
            withScheme = trimmed
        } else if trimmed.hasPrefix("/") {
            withScheme = "file://" + trimmed
        } else {
            withScheme = "http://" + trimmed
        }
        guard let url = URL(string: withScheme) else { return }
        loadedURL = url
        urlText = withScheme
    }
}

private struct SuggestionChip: View {
    let suggestion: DevServerDetector.Suggestion
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                liveDot
                Image(systemName: confidenceIcon)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.Color.accent)
                Text(suggestion.framework)
                    .font(Theme.Typography.micro.weight(.medium))
                    .foregroundStyle(Theme.Color.text)
                Text(":\(suggestion.port)")
                    .font(Theme.Typography.monoSmall)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(hovering ? Theme.Color.surfaceHi : (suggestion.isAlive == true ? SwiftUI.Color.green.opacity(0.10) : Theme.Color.surface))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(suggestion.isAlive == true ? .green : Theme.Color.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
            .opacity(suggestion.isAlive == false ? 0.55 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(helpText)
    }

    @ViewBuilder
    private var liveDot: some View {
        if let alive = suggestion.isAlive {
            Circle()
                .fill(alive ? SwiftUI.Color.green : SwiftUI.Color.red.opacity(0.5))
                .frame(width: 5, height: 5)
        }
    }

    private var confidenceIcon: String {
        switch suggestion.confidence {
        case .high: return "checkmark.seal.fill"
        case .medium: return "questionmark.circle"
        case .low: return "questionmark.diamond"
        }
    }

    private var helpText: String {
        let liveLabel: String
        switch suggestion.isAlive {
        case .some(true): liveLabel = "● 응답 중 — "
        case .some(false): liveLabel = "○ 응답 없음 (서버 시작 안 됨) — "
        case .none: liveLabel = ""
        }
        return "\(liveLabel)\(suggestion.framework) \(suggestion.confidence.label) — \(suggestion.url) 로드"
    }
}

private struct WebViewWrapper: NSViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastLoadedURL != url {
            webView.load(URLRequest(url: url))
            context.coordinator.lastLoadedURL = url
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: WebViewWrapper
        var lastLoadedURL: URL?

        init(parent: WebViewWrapper) {
            self.parent = parent
            self.lastLoadedURL = parent.url
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async { self.parent.isLoading = true }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async { self.parent.isLoading = false }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            DispatchQueue.main.async { self.parent.isLoading = false }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            DispatchQueue.main.async { self.parent.isLoading = false }
        }
    }
}
