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
    public let onCreatePR: (() -> Void)?

    public init(
        text: Binding<String>,
        model: Binding<ClaudeModel>,
        permissionMode: Binding<PermissionMode>,
        effortLevel: Binding<EffortLevel>,
        isStreaming: Bool,
        placeholder: String = "무엇을 도와드릴까요?  `/` 로 명령, `@` 로 노트",
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
        onCreatePR: (() -> Void)? = nil
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
        self.onCreatePR = onCreatePR
    }

    @FocusState private var inputFocused: Bool

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
        }
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
