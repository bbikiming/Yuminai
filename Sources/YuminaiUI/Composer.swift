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
    /// **ADR-088** — Codex CLI용 별도 모델 binding.
    @Binding public var codexModel: CodexModel
    @Binding public var permissionMode: PermissionMode
    @Binding public var effortLevel: EffortLevel
    /// **ADR-087 Phase 2** — Composer 안에서 직접 agent 전환 가능.
    /// nil이면 통합 picker 비활성 (기존 ModelPicker만 표시 — 후방 호환).
    @Binding public var agentKind: AgentKind

    public let isStreaming: Bool
    public let placeholder: String

    // 첨부
    public let attachedFiles: [URL]
    public let onRemoveAttachment: (URL) -> Void
    public let onClearAttachments: () -> Void

    // ADR-111 — 라이브러리 첨부
    /// 현재 첨부된 라이브러리 항목 목록.
    public let attachedLibraryItems: [YuminaiCore.ResourceLibraryItem]
    public let onRemoveLibraryItem: (YuminaiCore.ResourceLibraryItem) -> Void
    /// 라이브러리 picker popover 표시 콜백.
    public let onAttachLibrary: (() -> Void)?

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
    /// **ADR-087 Phase 2** — agent 전환 콜백 (RootView에서 setActiveAgentKind 호출).
    public let onSelectAgent: (AgentKind) -> Void
    /// **ADR-087 Phase 2** — Codex CLI 가용 여부 (disabled state 표시용).
    public let codexAvailable: Bool

    /// `@` 입력 시 자동완성 후보 (ADR-032). 빈 배열이면 picker 비활성.
    public let mentionSuggestions: [MentionSuggestion]

    /// **ADR-132** — 자동 실행 상태 (nil이면 자동 실행 버튼 비활성).
    public let autoRunState: AutoRunCoordinator.State?
    /// **ADR-132** — 자동 실행 최대 turn 수 (토글 레이블용).
    public let autoRunMaxTurns: Int
    /// **ADR-132** — 자동 실행 버튼 클릭 콜백 (현재 text를 initialPrompt로 전달).
    public let onAutoRun: ((String) -> Void)?

    /// **ADR-151** — 텔레그램 핸드오프 버튼 클릭 콜백 (nil이면 버튼 숨김).
    public let onTelegramHandoff: (() -> Void)?
    /// **ADR-151** — 텔레그램 핸드오프 가능 여부 (봇 활성화 + binding 있을 때 true).
    public let telegramHandoffAvailable: Bool

    /// **ADR-072 Phase 1** — 반응형 padding 결정용.
    public let layoutMode: LayoutMode

    public init(
        text: Binding<String>,
        model: Binding<ClaudeModel>,
        codexModel: Binding<CodexModel> = .constant(.default),
        permissionMode: Binding<PermissionMode>,
        effortLevel: Binding<EffortLevel>,
        agentKind: Binding<AgentKind> = .constant(.default),
        isStreaming: Bool,
        placeholder: String = "무엇을 도와드릴까요?  `@codex` 또는 `@claude`로 다른 pane에 위임",
        attachedFiles: [URL] = [],
        onRemoveAttachment: @escaping (URL) -> Void = { _ in },
        onClearAttachments: @escaping () -> Void = {},
        attachedLibraryItems: [YuminaiCore.ResourceLibraryItem] = [],
        onRemoveLibraryItem: @escaping (YuminaiCore.ResourceLibraryItem) -> Void = { _ in },
        onAttachLibrary: (() -> Void)? = nil,
        gitBranch: String? = nil,
        gitDiffPlus: Int? = nil,
        gitDiffMinus: Int? = nil,
        onSend: @escaping () -> Void,
        onStop: @escaping () -> Void,
        onSettingsApply: @escaping (SessionSettings) -> Void,
        onAttach: @escaping () -> Void = {},
        onAttachNote: (() -> Void)? = nil,
        onCreatePR: (() -> Void)? = nil,
        onSelectAgent: @escaping (AgentKind) -> Void = { _ in },
        codexAvailable: Bool = false,
        mentionSuggestions: [MentionSuggestion] = [],
        agentChainEnabled: Bool = false,
        layoutMode: LayoutMode = .regular,
        autoRunState: AutoRunCoordinator.State? = nil,
        autoRunMaxTurns: Int = 30,
        onAutoRun: ((String) -> Void)? = nil,
        onTelegramHandoff: (() -> Void)? = nil,
        telegramHandoffAvailable: Bool = false
    ) {
        self._text = text
        self._model = model
        self._codexModel = codexModel
        self._permissionMode = permissionMode
        self._effortLevel = effortLevel
        self._agentKind = agentKind
        self.isStreaming = isStreaming
        self.placeholder = placeholder
        self.attachedFiles = attachedFiles
        self.onRemoveAttachment = onRemoveAttachment
        self.onClearAttachments = onClearAttachments
        self.attachedLibraryItems = attachedLibraryItems
        self.onRemoveLibraryItem = onRemoveLibraryItem
        self.onAttachLibrary = onAttachLibrary
        self.gitBranch = gitBranch
        self.gitDiffPlus = gitDiffPlus
        self.gitDiffMinus = gitDiffMinus
        self.onSend = onSend
        self.onStop = onStop
        self.onSettingsApply = onSettingsApply
        self.onAttach = onAttach
        self.onAttachNote = onAttachNote
        self.onCreatePR = onCreatePR
        self.onSelectAgent = onSelectAgent
        self.codexAvailable = codexAvailable
        self.mentionSuggestions = mentionSuggestions
        self.agentChainEnabled = agentChainEnabled
        self.layoutMode = layoutMode
        self.autoRunState = autoRunState
        self.autoRunMaxTurns = autoRunMaxTurns
        self.onAutoRun = onAutoRun
        self.onTelegramHandoff = onTelegramHandoff
        self.telegramHandoffAvailable = telegramHandoffAvailable
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
            .background(agentChainEnabled ? Theme.Color.accentMuted.opacity(0.4) : Theme.Color.warningStrong.opacity(0.08))
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // ADR-111 — 라이브러리 첨부 chips (파일 첨부보다 위에)
            if !attachedLibraryItems.isEmpty {
                libraryAttachmentChips
                FlatHDivider().opacity(0.5)
            }
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
        // ADR-087 Phase 3 — 좌측 4px agent 색상 strip (사용자가 어느 agent로 보내는지 즉각 인지)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(agentKind.brandColor)
                .frame(width: 3)
                .accessibilityHidden(true)
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.xl)
                .stroke(inputFocused ? Theme.Color.borderStrong : Theme.Color.borderSubtle,
                        lineWidth: Theme.Stroke.hairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl))
        // ADR-087 Phase 3 — Composer 전체 background에 subtle agent 색상 tint (1.5% opacity)
        .shadow(color: agentKind.brandColor.opacity(inputFocused ? 0.12 : 0.04),
                radius: inputFocused ? 8 : 4, y: 2)
        .animation(.easeOut(duration: 0.20), value: agentKind)
        // ADR-072 Phase 1 — 반응형 outer padding (작은 화면에서 잘림 방지)
        .padding(.horizontal, Theme.Layout.composerOuterPadding(for: layoutMode))
        .padding(.bottom, Theme.Layout.composerOuterPadding(for: layoutMode))
        .padding(.top, Theme.Spacing.sm)
    }

    // MARK: - ADR-111 라이브러리 첨부 chips

    private var libraryAttachmentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(attachedLibraryItems) { item in
                    LibraryAttachmentChip(item: item, onRemove: { onRemoveLibraryItem(item) })
                }
            }
            .padding(.horizontal, Theme.Layout.composerPadding)
            .padding(.vertical, Theme.Spacing.sm)
        }
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
                // ADR-071 Phase 4 — VoiceOver
                .accessibilityLabel("메시지 입력")
                .accessibilityHint(text.isEmpty ? placeholder : "메시지 작성 중. Enter 키로 전송, Shift+Enter로 줄바꿈.")
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

    /// **ADR-072 Phase 1** — 작은 화면에서는 effort/note picker 등 비필수 요소 숨김.
    private var hidesSecondaryFooterItems: Bool {
        switch layoutMode {
        case .tiny, .compact: return true
        case .medium, .regular, .wide: return false
        }
    }

    /// **ADR-072 Phase 1** — tiny 모드에서는 model/mode picker도 가장 단순화.
    private var hidesAllPickers: Bool {
        layoutMode == .tiny
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // ADR-072 Phase 1 — 반응형 picker 표시
            if !hidesAllPickers {
                // ADR-087 Phase 2 + ADR-088 — 통합 Agent·Model picker (Claude/Codex 분리 모델)
                UnifiedAgentModelPicker(
                    agent: $agentKind,
                    claudeModel: $model,
                    codexModel: $codexModel,
                    codexAvailable: codexAvailable,
                    onAgentChange: { newAgent in
                        // RootView가 setActiveAgentKind 호출 → perAgentSettings swap 트리거
                        onSelectAgent(newAgent)
                    },
                    onClaudeModelChange: { _ in apply() },
                    onCodexModelChange: { _ in apply() }
                )
                ModePicker(selection: $permissionMode) { _ in apply() }
                if !hidesSecondaryFooterItems {
                    EffortPicker(selection: $effortLevel) { _ in apply() }
                }
            }

            Spacer(minLength: Theme.Spacing.xs)

            IconButton(
                "paperclip",
                size: 13,
                help: "파일이나 폴더를 첨부합니다. Claude가 자동으로 살펴봐요.",
                action: onAttach
            )

            // ADR-111 — 라이브러리 첨부 버튼
            if let onAttachLibrary, !hidesSecondaryFooterItems {
                IconButton(
                    "books.vertical",
                    size: 13,
                    help: "라이브러리 자료를 메시지에 첨부합니다.",
                    action: onAttachLibrary
                )
            }

            if let onAttachNote, !hidesSecondaryFooterItems {
                IconButton(
                    "doc.text",
                    size: 13,
                    help: "Obsidian 노트를 첨부합니다.",
                    action: onAttachNote
                )
            }

            if !mentionSuggestions.isEmpty && !hidesSecondaryFooterItems {
                delegateMenu
            }

            if isStreaming && !hidesSecondaryFooterItems {
                HStack(spacing: 4) {
                    PulseDot(color: Theme.Color.liveDot, size: 6)
                        .accessibilityHidden(true)
                    Text("응답 중")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.liveDot)
                }
            }

            // ADR-132 — 자동 실행 토글 버튼 (onAutoRun이 있을 때만)
            if let onAutoRun, let state = autoRunState, !hidesSecondaryFooterItems {
                AutoRunToggle(state: state, maxTurns: autoRunMaxTurns) {
                    onAutoRun(text)
                }
            }

            // ADR-151 — 텔레그램 핸드오프 버튼 (onTelegramHandoff 주입 + secondary 아님, 항상 표시)
            if let onTelegramHandoff, !hidesSecondaryFooterItems {
                TelegramHandoffButton(
                    isAvailable: telegramHandoffAvailable,
                    onTap: onTelegramHandoff
                )
            }

            // SendButton은 항상 보장 (가장 중요)
            SendButton(
                isStreaming: isStreaming,
                isEnabled: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                onSend: onSend,
                onStop: onStop
            )
            .layoutPriority(2)
        }
        .padding(.horizontal, Theme.Layout.composerPadding(for: layoutMode))
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

// MARK: - ADR-111 라이브러리 첨부 chip

/// 라이브러리 항목 첨부 chip — 파일 첨부 chip과 같은 스타일, 📚 아이콘 차별화.
struct LibraryAttachmentChip: View {
    let item: YuminaiCore.ResourceLibraryItem
    let onRemove: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.orange)
            Text(item.displayName)
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
        .frame(maxWidth: 220)
        .animation(.easeOut(duration: 0.10), value: hovering)
        .onHover { hovering = $0 }
        .help("라이브러리: \(item.displayName) (\(item.byteSizeDisplay))")
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
