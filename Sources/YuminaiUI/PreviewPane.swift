import SwiftUI
import WebKit

/// WKWebView 기반 임베드 preview pane (ADR-034 A4).
///
/// **use case**:
/// - dev server localhost (예: `http://localhost:3000`)
/// - file:// URL (예: 정적 HTML preview)
/// - 외부 docs URL (예: `https://docs.swift.org`)
///
/// 단순화 — 사용자가 URL TextField에 직접 입력. dev server auto-detect는 v0.6.
public struct PreviewPane: View {
    @Binding public var urlText: String
    public let onClose: () -> Void

    @State private var loadedURL: URL?
    @State private var isLoading: Bool = false

    public init(urlText: Binding<String>, onClose: @escaping () -> Void) {
        self._urlText = urlText
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            urlBar
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
            message: "dev server (`http://localhost:3000`)나 정적 HTML(`file:///...`)을 입력하고 Return을 누르면 표시됩니다.",
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
