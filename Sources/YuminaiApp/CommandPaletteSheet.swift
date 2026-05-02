import SwiftUI
import YuminaiCore
import YuminaiUI

/// ⌘K Command Palette (ADR-051) — Linear Method 패턴.
///
/// 모든 harness/workspace action을 한 곳에서 fuzzy search + 실행.
/// 사용자가 ⌘K 누르면 sheet 열림 → 검색 → ↑↓ navigate → ↩︎ 실행.
struct CommandPaletteSheet: View {
    let actions: [PaletteAction]
    let onPerform: (PaletteAction) -> Void
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
        .frame(width: 540, height: 400)
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

    private var filtered: [PaletteAction] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            return actions  // 카테고리 순서 그대로
        }
        return actions
            .compactMap { action -> (PaletteAction, Int)? in
                let titleScore = action.title.lowercased().contains(q) ? 100 : 0
                let subtitleScore = action.subtitle.lowercased().contains(q) ? 50 : 0
                let categoryScore = action.category.lowercased().contains(q) ? 20 : 0
                let total = titleScore + subtitleScore + categoryScore
                return total > 0 ? (action, total) : nil
            }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }

    @ViewBuilder
    private var resultsList: some View {
        let results = filtered
        if results.isEmpty {
            EmptyStateHint(
                icon: "questionmark.circle",
                title: "‘\(query)’와 매치되는 명령이 없어요",
                message: "다른 키워드로 시도하세요 — 예: ‘decompose’, ‘model claude’, ‘task’"
            )
            .frame(maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(Array(results.prefix(50).enumerated()), id: \.element.id) { idx, action in
                            CommandRow(
                                action: action,
                                selected: idx == selectedIndex,
                                onTap: {
                                    selectedIndex = idx
                                    performCurrent()
                                }
                            )
                            .id(idx)
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

    private func performCurrent() {
        let results = filtered
        guard selectedIndex < results.count else { return }
        onPerform(results[selectedIndex])
    }
}

/// Command palette action.
public struct PaletteAction: Identifiable, Equatable {
    public let id = UUID()
    public let category: String
    public let title: String
    public let subtitle: String
    public let icon: String
    public let shortcut: String?
    /// caller가 실행 — closure를 직접 보존 (Equatable 비교는 id로만)
    public let perform: () -> Void

    public init(
        category: String,
        title: String,
        subtitle: String = "",
        icon: String = "circle",
        shortcut: String? = nil,
        perform: @escaping () -> Void
    ) {
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
    let onTap: () -> Void

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
