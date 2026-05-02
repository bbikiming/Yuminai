import SwiftUI
import YuminaiCore
import YuminaiUI

/// ⌘K Command Palette (ADR-051 + ADR-052) — Linear Method + VSCode/Raycast pin pattern.
///
/// 모든 harness/workspace action을 한 곳에서 fuzzy search + 실행.
/// 사용자가 ⌘K 누르면 sheet 열림 → 검색 → ↑↓ navigate → ↩︎ 실행.
///
/// **ADR-052 추가**:
/// - ★ pin/unpin (각 row에 별 아이콘) — VSCode `quickPickPin.ts` 패턴
/// - 검색 비어있을 때 "Pinned" / "Recent" / "All" 섹션 분리
/// - 검색 중에는 pin section 자동 숨김 (cmdk linear.tsx 패턴)
/// - cmdk fuzzy scoring (continuous=1.0, word-jump=0.8-0.9)
struct CommandPaletteSheet: View {
    let actions: [PaletteAction]
    let pinnedIds: [String]
    let recentIds: [String]
    let onPerform: (PaletteAction) -> Void
    let onTogglePin: (String) -> Void
    let onCancel: () -> Void

    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            FlatHDivider()
            resultsList
        }
        .frame(width: 560, height: 460)
        .background(Theme.Color.bg)
        .onAppear { inputFocused = true }
    }

    private var searchHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "command")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Color.accent)
            TextField("명령 검색…", text: $query)
                .textFieldStyle(.plain)
                .font(Theme.Typography.body)
                .focused($inputFocused)
                .onSubmit { performCurrent() }
                .onChange(of: query) { _, _ in selectedIndex = 0 }
            Text("Esc")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Theme.Color.surfaceHi)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .padding(Theme.Spacing.md)
    }

    /// ADR-052 — section 분리: 검색 빈 상태에서만 Pinned/Recent를 보여주고, 검색 중엔 합쳐서 score-rank.
    private var sections: [PaletteSection] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            // Empty query: Pinned / Recent / All 분리
            let pinned = pinnedIds.compactMap { id in actions.first { $0.actionId == id } }
            let recent = recentIds
                .filter { !pinnedIds.contains($0) }
                .compactMap { id in actions.first { $0.actionId == id } }
            let pinnedSet = Set(pinned.map(\.id))
            let recentSet = Set(recent.map(\.id))
            let others = actions.filter { !pinnedSet.contains($0.id) && !recentSet.contains($0.id) }
            var result: [PaletteSection] = []
            if !pinned.isEmpty { result.append(PaletteSection(title: "★ 핀", actions: pinned)) }
            if !recent.isEmpty { result.append(PaletteSection(title: "최근", actions: recent)) }
            if !others.isEmpty { result.append(PaletteSection(title: "전체", actions: others)) }
            return result
        }
        // 검색 중: cmdk fuzzy score
        let scored = actions.compactMap { action -> (PaletteAction, Double)? in
            let titleScore = CmdkScore.score(text: action.title, query: q) * 1.5
            let subtitleScore = CmdkScore.score(text: action.subtitle, query: q) * 0.7
            let categoryScore = CmdkScore.score(text: action.category, query: q) * 0.4
            let total = titleScore + subtitleScore + categoryScore
            return total > 0.3 ? (action, total) : nil
        }
        .sorted { $0.1 > $1.1 }
        .map { $0.0 }
        return scored.isEmpty ? [] : [PaletteSection(title: "검색 결과", actions: scored)]
    }

    /// 평탄화된 액션 리스트 (selectedIndex navigation용).
    private var flatActions: [PaletteAction] {
        sections.flatMap { $0.actions }
    }

    @ViewBuilder
    private var resultsList: some View {
        let results = flatActions
        if results.isEmpty {
            EmptyStateHint(
                icon: "questionmark.circle",
                title: query.isEmpty ? "사용 가능한 명령이 없어요" : "‘\(query)’와 매치되는 명령이 없어요",
                message: "다른 키워드로 시도하세요 — 예: ‘decompose’, ‘model claude’, ‘routing log’"
            )
            .frame(maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // 평탄화 인덱스 추적
                        var globalIdx = -1
                        ForEach(sections, id: \.title) { section in
                            sectionHeader(section.title)
                            ForEach(section.actions, id: \.id) { action in
                                let _ = (globalIdx += 1)
                                CommandRow(
                                    action: action,
                                    selected: globalIdx == selectedIndex,
                                    isPinned: pinnedIds.contains(action.actionId) && !action.actionId.isEmpty,
                                    onTap: {
                                        selectedIndex = globalIdx
                                        performCurrent()
                                    },
                                    onTogglePin: { onTogglePin(action.actionId) }
                                )
                                .id(globalIdx)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onChange(of: selectedIndex) { _, newValue in
                    withAnimation(.easeOut(duration: 0.10)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
                .background(KeyEventCatcher(
                    onUp: { selectedIndex = max(0, selectedIndex - 1) },
                    onDown: { selectedIndex = min(results.count - 1, selectedIndex + 1) }
                ))
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Theme.Typography.micro)
            .foregroundStyle(Theme.Color.textTertiary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func performCurrent() {
        let results = flatActions
        guard selectedIndex < results.count else { return }
        onPerform(results[selectedIndex])
    }
}

struct PaletteSection {
    let title: String
    let actions: [PaletteAction]
}

/// Command palette action.
///
/// **ADR-052** — `actionId` (stable string ID) 추가. VSCode `quickPickPin.ts` /
/// Raycast clean-text pattern 차용: pin/recent storage는 ID 배열로만 관리.
/// 객체 자체를 저장하지 않으므로 label/icon/handler 변경에도 깨지지 않음.
public struct PaletteAction: Identifiable, Equatable {
    public let id = UUID()
    /// **ADR-052** — pin/recent 영속 키. 의미적으로 안정 (예: "harness.toggle.routing").
    /// 비어있으면 pin/recent 추적 X (1회성 액션).
    public let actionId: String
    public let category: String
    public let title: String
    public let subtitle: String
    public let icon: String
    public let shortcut: String?
    /// caller가 실행 — closure를 직접 보존 (Equatable 비교는 id로만)
    public let perform: () -> Void

    public init(
        actionId: String = "",
        category: String,
        title: String,
        subtitle: String = "",
        icon: String = "circle",
        shortcut: String? = nil,
        perform: @escaping () -> Void
    ) {
        self.actionId = actionId
        self.category = category
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.shortcut = shortcut
        self.perform = perform
    }

    public static func == (lhs: PaletteAction, rhs: PaletteAction) -> Bool {
        lhs.id == rhs.id
    }
}

private struct CommandRow: View {
    let action: PaletteAction
    let selected: Bool
    let isPinned: Bool
    let onTap: () -> Void
    let onTogglePin: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: action.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Color.textSecondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(action.title)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Color.text)
                        Text(action.category)
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.textTertiary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Theme.Color.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    if !action.subtitle.isEmpty {
                        Text(action.subtitle)
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                // ADR-052 — pin toggle (actionId 있는 액션만)
                if !action.actionId.isEmpty {
                    Button(action: onTogglePin) {
                        Image(systemName: isPinned ? "star.fill" : "star")
                            .font(.system(size: 11))
                            .foregroundStyle(isPinned ? Color.yellow : Theme.Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help(isPinned ? "핀 해제" : "★ 핀 — 항상 상단 표시")
                }
                if let shortcut = action.shortcut {
                    Text(shortcut)
                        .font(Theme.Typography.monoSmall)
                        .foregroundStyle(Theme.Color.textTertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Theme.Color.surfaceHi)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 6)
            .background(selected ? Theme.Color.accentMuted : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 화살표 키 capture — NSEvent monitor 대신 .focused state로 빠른 제어.
private struct KeyEventCatcher: NSViewRepresentable {
    let onUp: () -> Void
    let onDown: () -> Void

    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
