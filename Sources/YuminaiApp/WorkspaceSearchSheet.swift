import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-078 Phase 3** — 워크스페이스 fuzzy search sheet (⌘P).
///
/// 검색 대상:
/// - 워크스페이스 이름 (가장 높은 가중치)
/// - 디렉토리 경로 (last component 우선)
/// - 폴더 이름 (워크스페이스가 속한)
/// - 핀 / 텔레그램 연결 / 보관 상태 (필터)
///
/// 결과 표시:
/// - 워크스페이스 이름 + 경로 + 메타 (폴더, 핀, 텔레그램, 마지막 사용)
/// - ↑↓ navigation + Enter 선택 + Esc 취소
struct WorkspaceSearchSheet: View {
    let workspaces: [Workspace]
    let folders: [WorkspaceFolder]
    let pinnedIds: [UUID]
    let telegramBoundId: UUID?
    let chatBindings: [String: UUID]
    let onSelect: (UUID) -> Void
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
        .yuminaiSheetFrame(width: 580, height: 480, wrapInScrollView: false)
        .background(Theme.Color.bg)
        .onAppear { inputFocused = true }
        .onKeyPress(.downArrow) {
            moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.escape) {
            onCancel()
            return .handled
        }
    }

    private func moveSelection(by delta: Int) {
        let count = filtered.prefix(50).count
        guard count > 0 else { return }
        let next = ((selectedIndex + delta) % count + count) % count
        selectedIndex = next
    }

    private var searchHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Color.textSecondary)
            TextField("워크스페이스 검색…", text: $query)
                .textFieldStyle(.plain)
                .font(Theme.Typography.body)
                .focused($inputFocused)
                .onSubmit { selectCurrent() }
                .onChange(of: query) { _, _ in selectedIndex = 0 }
                .accessibilityLabel("워크스페이스 검색")
                .accessibilityHint("이름, 경로, 폴더 이름으로 검색합니다")
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

    /// 워크스페이스 + score 계산.
    private var filtered: [(workspace: Workspace, score: Int, folderName: String?)] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let folderById = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        let folderForWorkspace: (UUID) -> String? = { wsId in
            folders.first(where: { $0.workspaceIds.contains(wsId) })?.name
        }

        if q.isEmpty {
            // 빈 query: 핀 우선, 그 다음 lastOpenedAt 최신 순
            return workspaces
                .map { ws -> (Workspace, Int, String?) in
                    let isPinned = pinnedIds.contains(ws.id)
                    let folderName = folderForWorkspace(ws.id)
                    let score = isPinned ? 100 : 0
                    return (ws, score, folderName)
                }
                .sorted { lhs, rhs in
                    if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }  // 핀 먼저
                    return (lhs.0.lastOpenedAt ?? .distantPast) > (rhs.0.lastOpenedAt ?? .distantPast)
                }
        }

        return workspaces.compactMap { ws in
            let nameLower = ws.name.lowercased()
            let pathLower = ws.directoryPath.lowercased()
            let folderName = folderForWorkspace(ws.id)
            let folderLower = folderName?.lowercased() ?? ""

            var score = 0
            // 이름 prefix match (최고 점수)
            if nameLower.hasPrefix(q) { score += 100 }
            // 이름 contains
            else if nameLower.contains(q) { score += 50 }
            // 경로 마지막 component prefix
            else if let lastComponent = ws.directoryPath.split(separator: "/").last,
                    String(lastComponent).lowercased().hasPrefix(q) { score += 80 }
            // 경로 contains
            else if pathLower.contains(q) { score += 20 }
            // 폴더 이름 contains
            else if folderLower.contains(q) { score += 30 }
            else { return nil }

            // 핀된 항목 보너스
            if pinnedIds.contains(ws.id) { score += 10 }
            // 짧은 이름 보너스 (정확한 매칭 우선)
            score += max(0, 30 - ws.name.count)

            _ = folderById  // suppress warning
            return (ws, score, folderName)
        }
        .sorted { $0.1 > $1.1 }
    }

    @ViewBuilder
    private var resultsList: some View {
        let matches = filtered
        if matches.isEmpty {
            EmptyStateHint(
                icon: query.isEmpty ? "folder.badge.questionmark" : "questionmark.folder",
                title: query.isEmpty ? "워크스페이스가 없어요" : "매칭되는 워크스페이스 없음",
                message: query.isEmpty
                    ? "워크스페이스를 만들거나 기존 폴더를 가져오세요."
                    : "‘\(query)’와 매칭되는 워크스페이스가 없습니다. 이름, 경로, 폴더 이름으로 검색해 보세요."
            )
            .frame(maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(Array(matches.prefix(50).enumerated()), id: \.element.workspace.id) { idx, match in
                            WorkspaceMatchRow(
                                workspace: match.workspace,
                                folderName: match.folderName,
                                isPinned: pinnedIds.contains(match.workspace.id),
                                isTelegramBound: SmartFolderEvaluator.isTelegramBound(
                                    workspaceId: match.workspace.id,
                                    boundId: telegramBoundId,
                                    chatBindings: chatBindings
                                ),
                                selected: idx == selectedIndex,
                                onTap: {
                                    selectedIndex = idx
                                    selectCurrent()
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
            }
        }
    }

    private func selectCurrent() {
        let matches = filtered
        guard selectedIndex < matches.count else { return }
        onSelect(matches[selectedIndex].workspace.id)
    }
}

private struct WorkspaceMatchRow: View {
    let workspace: Workspace
    let folderName: String?
    let isPinned: Bool
    let isTelegramBound: Bool
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // 워크스페이스 아이콘 (folder.fill 또는 핀)
                Image(systemName: isPinned ? "pin.fill" : "folder.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(isPinned ? Theme.Color.accent : Theme.Color.textSecondary)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(workspace.name)
                            .font(Theme.Typography.body.weight(.medium))
                            .foregroundStyle(Theme.Color.text)
                        if isTelegramBound {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.Color.accent)
                                .accessibilityHidden(true)
                        }
                    }
                    HStack(spacing: 6) {
                        Text(workspace.directoryPath)
                            .font(Theme.Typography.monoSmall)
                            .foregroundStyle(Theme.Color.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let folderName {
                            Text("· \(folderName)")
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Color.textTertiary)
                        }
                    }
                }
                Spacer()
                if let lastOpened = workspace.lastOpenedAt {
                    Text(relativeTimeString(lastOpened))
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 8)
            .background(selected ? Theme.Color.accentMuted : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(workspace.name)\(isPinned ? ", 고정됨" : "")\(isTelegramBound ? ", 텔레그램 연결됨" : "")\(folderName.map { ", 폴더 \($0)" } ?? "")")
    }

    /// 한국어 friendly relative time (e.g., "3분 전", "어제", "3일 전").
    private func relativeTimeString(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "방금 전" }
        if interval < 3600 { return "\(Int(interval / 60))분 전" }
        if interval < 86400 { return "\(Int(interval / 3600))시간 전" }
        if interval < 86400 * 7 { return "\(Int(interval / 86400))일 전" }
        if interval < 86400 * 30 { return "\(Int(interval / (86400 * 7)))주 전" }
        return "\(Int(interval / (86400 * 30)))개월 전"
    }
}
