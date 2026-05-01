import SwiftUI
import YuminaiCore

/// Yuminai Composer v3 — 채팅 입력 영역.
///
/// 명세 §8.8 (codex review #3 반영). 구조:
/// 1. (옵션) 첨부 파일 chips
/// 2. (옵션) git/diff meta row
/// 3. TextEditor + placeholder
/// 4. footer: model/mode/effort picker · attachment · send/stop
public struct Composer: View {
    @Binding public var text: String
    @Binding public var model: ClaudeModel
    @Binding public var permissionMode: PermissionMode
    @Binding public var effortLevel: EffortLevel

    public let isStreaming: Bool
    public let placeholder: String

    // 첨부
    public let attachedFiles: [URL]
    public let onRemoveAttachment: (URL) -> Void
    public let onClearAttachments: () -> Void

    // Optional git meta
    public let gitBranch: String?
    public let gitDiffPlus: Int?
    public let gitDiffMinus: Int?

    public let onSend: () -> Void
    public let onStop: () -> Void
    public let onSettingsApply: (SessionSettings) -> Void
    public let onAttach: () -> Void
    public let onAttachNote: (() -> Void)?
    public let onCreatePR: (() -> Void)?

    /// `@` 입력 시 자동완성 후보 (ADR-032). 빈 배열이면 picker 비활성.
    public let mentionSuggestions: [MentionSuggestion]

    public init(
        text: Binding<String>,
        model: Binding<ClaudeModel>,
        permissionMode: Binding<PermissionMode>,
        effortLevel: Binding<EffortLevel>,
        isStreaming: Bool,
        placeholder: String = "무엇을 도와드릴까요?  `@codex` 또는 `@claude`로 다른 pane에 위임",
        attachedFiles: [URL] = [],
        onRemoveAttachment: @escaping (URL) -> Void = { _ in },
        onClearAttachments: @escaping () -> Void = {},
        gitBranch: String? = nil,
        gitDiffPlus: Int? = nil,
        gitDiffMinus: Int? = nil,
        onSend: @escaping () -> Void,
        onStop: @escaping () -> Void,
        onSettingsApply: @escaping (SessionSettings) -> Void,
        onAttach: @escaping () -> Void = {},
        onAttachNote: (() -> Void)? = nil,
        onCreatePR: (() -> Void)? = nil,
        mentionSuggestions: [MentionSuggestion] = [],
        agentChainEnabled: Bool = false
    ) {
        self._text = text
        self._model = model
        self._permissionMode = permissionMode
        self._effortLevel = effortLevel
        self.isStreaming = isStreaming
        self.placeholder = placeholder
        self.attachedFiles = attachedFiles
        self.onRemoveAttachment = onRemoveAttachment
        self.onClearAttachments = onClearAttachments
        self.gitBranch = gitBranch
        self.gitDiffPlus = gitDiffPlus
        self.gitDiffMinus = gitDiffMinus
        self.onSend = onSend
        self.onStop = onStop
        self.onSettingsApply = onSettingsApply
        self.onAttach = onAttach
        self.onAttachNote = onAttachNote
        self.onCreatePR = onCreatePR
        self.mentionSuggestions = mentionSuggestions
        self.agentChainEnabled = agentChainEnabled
    }

    @FocusState private var inputFocused: Bool
    @State private var showMentionPicker = false

    private static let mentionParser = MentionParser()

    /// 여러 mention 발견 시 안내 (ADR-035 B3 + ADR-036 C2 chain 안내).
    /// chain 활성 시 sequential dispatch가 자동으로 일어남을 안내.
    public let agentChainEnabled: Bool

    @ViewBuilder
    private var multiMentionHint: some View {
        let mentions = Self.mentionParser.allInline(text)
        if mentions.count > 1 {
            HStack(spacing: 6) {
                Image(systemName: agentChainEnabled ? "link.circle.fill" : "info.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(agentChainEnabled ? Theme.Color.accent : .orange)
                if agentChainEnabled {
                    Text("Chain 활성 — 첫 번째 ‘\(mentions[0])’으로 시작, 응답에 다음 mention 있으면 chain hop으로 자동 dispatch됩니다.")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textSecondary)
                } else {
                    Text("여러 mention 발견 (\(mentions.joined(separator: ", "))) — 첫 번째 ‘\(mentions[0])’ 만 사용됩니다. Settings → Agent Chain ON 시 sequential dispatch 가능.")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 4)
            .background(agentChainEnabled ? Theme.Color.accentMuted.opacity(0.4) : SwiftUI.Color.orange.opacity(0.08))
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            if !attachedFiles.isEmpty {
                attachmentChips
                FlatHDivider().opacity(0.5)
            }
            if let gitBranch {
                gitMetaRow(branch: gitBranch)
                FlatHDivider().opacity(0.5)
            }
            multiMentionHint
            textArea
            footer
        }
        .background(Theme.Color.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.xl)
                .stroke(inputFocused ? Theme.Color.borderStrong : Theme.Color.borderSubtle,
                        lineWidth: Theme.Stroke.hairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl))
        .padding(.horizontal, Theme.Layout.composerOuterPadding)
        .padding(.bottom, Theme.Layout.composerOuterPadding)
        .padding(.top, Theme.Spacing.sm)
    }

    // MARK: - Attached files chips

    private var attachmentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(attachedFiles, id: \.self) { url in
                    AttachmentChip(url: url, onRemove: { onRemoveAttachment(url) })
                }
                if attachedFiles.count > 1 {
                    Button(action: onClearAttachments) {
                        Text("모두 지우기")
                            .font(Theme.Typography.small)
                            .foregroundStyle(Theme.Color.textTertiary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .help("첨부 모두 제거")
                }
            }
            .padding(.horizontal, Theme.Layout.composerPadding)
            .padding(.vertical, Theme.Spacing.sm)
        }
    }

    // MARK: - Git meta row

    private func gitMetaRow(branch: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.Color.textTertiary)

            Text(branch)
                .font(Theme.Typography.monoSmall)
                .foregroundStyle(Theme.Color.textSecondary)

            Spacer()

            if let plus = gitDiffPlus, let minus = gitDiffMinus {
                Text("+\(plus)")
                    .font(Theme.Typography.monoSmall)
                    .foregroundStyle(Theme.Color.diffPlus)
                Text("\(minus > 0 ? "−" : "")\(minus)")
                    .font(Theme.Typography.monoSmall)
                    .foregroundStyle(Theme.Color.diffMinus)
            }

            if let onCreatePR {
                FlatButton("PR 생성", icon: "arrow.up.circle", variant: .accentSubtle, size: .mini, action: onCreatePR)
            }
        }
        .padding(.horizontal, Theme.Layout.composerPadding)
        .padding(.vertical, Theme.Spacing.sm)
    }

    // MARK: - Text area

    private var textArea: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .padding(.horizontal, Theme.Layout.composerPadding + 4)
                    .padding(.vertical, Theme.Layout.composerPadding - 2)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Color.text)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, Theme.Layout.composerPadding - 4)
                .padding(.vertical, Theme.Layout.composerPadding - 8)
                .frame(minHeight: 80, maxHeight: Theme.Layout.composerMaxHeight - 80)
                .focused($inputFocused)
                .onChange(of: text) { _, newValue in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    let mentionInProgress = trimmed.hasPrefix("@") &&
                        !trimmed.contains(" ") &&
                        !trimmed.contains("\n")
                    showMentionPicker = mentionInProgress && !mentionSuggestions.isEmpty
                }
        }
        .popover(isPresented: $showMentionPicker, arrowEdge: .top) {
            mentionPickerContent
        }
    }

    private var mentionPickerContent: some View {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .dropFirst()  // remove leading @
            .lowercased()
        let filtered = mentionSuggestions.filter { sug in
            query.isEmpty ||
                sug.handle.lowercased().hasPrefix(String(query)) ||
                sug.displayName.lowercased().contains(String(query))
        }
        return VStack(alignment: .leading, spacing: 1) {
            if filtered.isEmpty {
                Text("매칭되는 pane이 없어요")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .padding(Theme.Spacing.md)
            } else {
                ForEach(filtered) { sug in
                    MentionRow(suggestion: sug) {
                        text = "@\(sug.handle) "
                        showMentionPicker = false
                        inputFocused = true
                    }
                }
            }
            Divider()
            Text("선택하면 해당 pane으로 위임돼요")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 4)
        }
        .frame(width: 280)
        .padding(.vertical, 4)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: Theme.Spacing.md) {
            ModelPicker(selection: $model) { _ in apply() }
            ModePicker(selection: $permissionMode) { _ in apply() }
            EffortPicker(selection: $effortLevel) { _ in apply() }

            Spacer()

            IconButton(
                "paperclip",
                size: 13,
                help: "파일이나 폴더를 첨부합니다. Claude가 자동으로 살펴봐요.",
                action: onAttach
            )

            if let onAttachNote {
                IconButton(
                    "doc.text",
                    size: 13,
                    help: "Obsidian 노트를 첨부합니다.",
                    action: onAttachNote
                )
            }

            if !mentionSuggestions.isEmpty {
                delegateMenu
            }

            if isStreaming {
                HStack(spacing: 4) {
                    PulseDot(color: Theme.Color.liveDot, size: 6)
                    Text("응답 중")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.liveDot)
                }
            }

            SendButton(
                isStreaming: isStreaming,
                isEnabled: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                onSend: onSend,
                onStop: onStop
            )
        }
        .padding(.horizontal, Theme.Layout.composerPadding)
        .padding(.vertical, Theme.Spacing.md - 2)
        .background(Theme.Color.surface.opacity(0.6))
        .overlay(alignment: .top) {
            FlatHDivider().opacity(0.5)
        }
    }

    private func apply() {
        onSettingsApply(SessionSettings(
            model: model,
            permissionMode: permissionMode,
            effortLevel: effortLevel
        ))
    }

    /// Composer footer "위임" 버튼 — mention picker의 GUI 등가물.
    /// 사용자가 `@` 기억 안 해도 클릭으로 다른 pane 선택 가능.
    private var delegateMenu: some View {
        Menu {
            Section("다른 pane에 위임") {
                ForEach(mentionSuggestions) { sug in
                    Button {
                        // 현재 text 앞에 mention prepend (또는 빈 text면 mention만)
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            text = "@\(sug.handle) "
                        } else if !trimmed.hasPrefix("@") {
                            text = "@\(sug.handle) " + text
                        } else {
                            text = "@\(sug.handle) " + trimmed
                        }
                    } label: {
                        HStack {
                            if sug.isPrimary {
                                Image(systemName: "star.fill")
                            }
                            Text("@\(sug.handle)  ·  \(sug.displayName)")
                            Text(sug.agentKindLabel).font(.caption2)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "arrowshape.turn.up.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Color.textSecondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("다른 pane으로 메시지 위임 (`@` 멘션과 동일)")
    }
}

// MARK: - Attachment chip

struct AttachmentChip: View {
    let url: URL
    let onRemove: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.Color.accent)
            Text(displayName)
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.text)
                .lineLimit(1)
                .truncationMode(.middle)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(hovering ? Theme.Color.danger : Theme.Color.textSecondary)
            }
            .buttonStyle(.plain)
            .help("이 첨부 제거")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(hovering ? Theme.Color.surfaceHi : Theme.Color.elevated)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .stroke(Theme.Color.borderSubtle, lineWidth: Theme.Stroke.hairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .frame(maxWidth: 200)
        .animation(.easeOut(duration: 0.10), value: hovering)
        .onHover { hovering = $0 }
        .help(url.path)
    }

    private var displayName: String {
        url.lastPathComponent
    }

    private var iconName: String {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if exists && isDir.boolValue { return "folder.fill" }
        // 확장자 기반 추정
        switch url.pathExtension.lowercased() {
        case "swift", "ts", "tsx", "js", "jsx", "py", "rs", "go", "java", "rb", "php", "cpp", "c", "h":
            return "doc.text.fill"
        case "md", "txt":
            return "doc.plaintext.fill"
        case "png", "jpg", "jpeg", "gif", "svg", "pdf":
            return "photo.fill"
        case "json", "yml", "yaml", "toml", "xml":
            return "curlybraces"
        default:
            return "doc.fill"
        }
    }
}

// MARK: - 메시지 메타 row (메시지 위)

public struct MessageMeta: View {
    public let timestamp: Date
    public let tokens: Int?

    public init(timestamp: Date, tokens: Int? = nil) {
        self.timestamp = timestamp
        self.tokens = tokens
    }

    public var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Theme.Color.textTertiary)
                .frame(width: 5, height: 5)
            Text(elapsedText)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
            if let tokens {
                Text("·")
                    .foregroundStyle(Theme.Color.textTertiary)
                Image(systemName: "arrow.down")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Theme.Color.textTertiary)
                Text(tokens.formattedShort)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                Text("tokens")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
            }
        }
        .padding(.horizontal, Theme.Layout.contentPaddingH)
    }

    private var elapsedText: String {
        let interval = Date().timeIntervalSince(timestamp)
        if interval < 60 { return "\(Int(interval))s" }
        if interval < 3600 {
            let m = Int(interval / 60)
            let s = Int(interval) % 60
            return "\(m)m \(s)s"
        }
        let h = Int(interval / 3600)
        return "\(h)h"
    }
}

// MARK: - Mention picker (ADR-032 U1)

/// `@` 입력 시 자동완성 후보. handle은 mention text (`@<handle>`).
public struct MentionSuggestion: Sendable, Identifiable, Hashable {
    public let id: String  // = handle (unique 가정)
    public let handle: String
    public let displayName: String
    public let agentKindLabel: String
    public let isPrimary: Bool

    public init(handle: String, displayName: String, agentKindLabel: String, isPrimary: Bool = false) {
        self.id = handle
        self.handle = handle
        self.displayName = displayName
        self.agentKindLabel = agentKindLabel
        self.isPrimary = isPrimary
    }
}

private struct MentionRow: View {
    let suggestion: MentionSuggestion
    let onSelect: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Text("@\(suggestion.handle)")
                    .font(Theme.Typography.monoSmall)
                    .foregroundStyle(Theme.Color.accent)
                Text(suggestion.displayName)
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.text)
                if suggestion.isPrimary {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.Color.accent)
                }
                Spacer()
                Text(suggestion.agentKindLabel)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 5)
            .background(hovering ? Theme.Color.surfaceHi : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
