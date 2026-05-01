import SwiftUI
import MarkdownUI
import YuminaiObsidian

/// Notion급 마크다운 렌더러 — `swift-markdown-ui` wrapping + Yuminai 테마.
///
/// `vaultRoot`가 있으면 wiki link `[[Page]]` + 이미지 임베드 `![[file]]`을 preprocess.
/// `onWikiLink` 콜백으로 wiki 링크 클릭 시 page 이름이 전달된다.
public struct MarkdownViewer: View {
    public let markdown: String
    public let vaultRoot: URL?
    public let noteResolver: ((String) -> String?)?
    public let onWikiLink: ((String) -> Void)?

    public init(
        markdown: String,
        vaultRoot: URL? = nil,
        noteResolver: ((String) -> String?)? = nil,
        onWikiLink: ((String) -> Void)? = nil
    ) {
        self.markdown = markdown
        self.vaultRoot = vaultRoot
        self.noteResolver = noteResolver
        self.onWikiLink = onWikiLink
    }

    public var body: some View {
        let processed = MarkdownPreprocessor.process(
            markdown,
            vaultRoot: vaultRoot,
            noteResolver: noteResolver
        )
        ScrollView {
            Markdown(processed)
                .markdownTheme(.yuminai)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .environment(\.openURL, OpenURLAction { url in
                    if url.scheme == "yuminai-note", let onWikiLink {
                        let page = url.host?.removingPercentEncoding
                            ?? url.path.removingPercentEncoding?.trimmingCharacters(in: .init(charactersIn: "/"))
                            ?? ""
                        onWikiLink(page)
                        return .handled
                    }
                    return .systemAction
                })
        }
        .background(Theme.Color.bg)
    }
}

// MARK: - Yuminai theme

extension Theme {
    /// MarkdownUI 테마 — 우리 토큰 적용. computed property로 두어 main actor 격리.
    @MainActor
    public enum MarkdownStyle {
        public static var theme: MarkdownUI.Theme {
            MarkdownUI.Theme()
            .text {
                ForegroundColor(Theme.Color.text)
                FontFamilyVariant(.normal)
                FontSize(14)
            }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(13)
                ForegroundColor(Theme.Color.text)
                BackgroundColor(Theme.Color.inlineCode)
            }
            .strong {
                FontWeight(.semibold)
            }
            .emphasis {
                FontStyle(.italic)
            }
            .link {
                ForegroundColor(Theme.Color.accent)
                UnderlineStyle(.single)
            }
            .heading1 { configuration in
                VStack(alignment: .leading, spacing: 0) {
                    configuration.label
                        .markdownTextStyle {
                            FontWeight(.bold)
                            FontSize(24)
                            ForegroundColor(Theme.Color.text)
                        }
                        .markdownMargin(top: 0, bottom: 16)
                    Divider().background(Theme.Color.borderSubtle)
                }
            }
            .heading2 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.bold)
                        FontSize(20)
                        ForegroundColor(Theme.Color.text)
                    }
                    .markdownMargin(top: 24, bottom: 12)
            }
            .heading3 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(17)
                        ForegroundColor(Theme.Color.text)
                    }
                    .markdownMargin(top: 20, bottom: 8)
            }
            .heading4 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(15)
                        ForegroundColor(Theme.Color.text)
                    }
                    .markdownMargin(top: 16, bottom: 6)
            }
            .paragraph { configuration in
                configuration.label
                    .markdownMargin(top: 0, bottom: 12)
                    .lineSpacing(4)
            }
            .blockquote { configuration in
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Theme.Color.accent)
                        .frame(width: 3)
                    configuration.label
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .markdownTextStyle {
                            ForegroundColor(Theme.Color.textSecondary)
                        }
                }
                .background(Theme.Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .markdownMargin(top: 8, bottom: 12)
            }
            .codeBlock { configuration in
                ScrollView(.horizontal, showsIndicators: false) {
                    configuration.label
                        .padding(12)
                        .markdownTextStyle {
                            FontFamilyVariant(.monospaced)
                            FontSize(12.5)
                            ForegroundColor(Theme.Color.text)
                        }
                }
                .background(Theme.Color.surface)
                .overlay(alignment: .topTrailing) {
                    if let lang = configuration.language, !lang.isEmpty {
                        Text(lang)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.Color.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.Color.elevated)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .padding(8)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                .markdownMargin(top: 8, bottom: 12)
            }
            .listItem { configuration in
                configuration.label
                    .markdownMargin(top: 0, bottom: 4)
            }
            .taskListMarker { configuration in
                Image(systemName: configuration.isCompleted ? "checkmark.square.fill" : "square")
                    .foregroundStyle(configuration.isCompleted ? Theme.Color.accent : Theme.Color.textSecondary)
                    .font(.system(size: 13))
            }
            .table { configuration in
                configuration.label
                    .markdownTableBorderStyle(.init(color: Theme.Color.borderSubtle))
                    .markdownTableBackgroundStyle(
                        .alternatingRows(Theme.Color.bg, Theme.Color.surface)
                    )
                    .markdownMargin(top: 8, bottom: 12)
            }
            .tableCell { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontSize(13)
                        ForegroundColor(Theme.Color.text)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .thematicBreak {
                Divider()
                    .background(Theme.Color.border)
                    .markdownMargin(top: 16, bottom: 16)
            }
        }
    }
}

extension MarkdownUI.Theme {
    /// Yuminai 디자인 토큰을 적용한 마크다운 테마.
    @MainActor
    public static var yuminai: MarkdownUI.Theme {
        Theme.MarkdownStyle.theme
    }
}
