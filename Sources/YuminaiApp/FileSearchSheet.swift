import SwiftUI
import YuminaiCore
import YuminaiUI

/// File search sheet — Cmd+P style fuzzy filter (ADR-038 E3).
///
/// **단순화**:
/// - flat 파일 목록 (트리 자동 평탄화)
/// - prefix match → bonus, substring match → 기본
/// - 최대 50개 결과 표시 (성능)
/// - Enter → 선택 + sheet 닫기, ESC → 취소
struct FileSearchSheet: View {
    let allFiles: [FileNode]
    let onSelect: (String) -> Void
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
        // ↑↓ 화살표 navigation — TextField focus 중에도 동작 (ADR-038 R2).
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
            TextField("파일 검색…", text: $query)
                .textFieldStyle(.plain)
                .font(Theme.Typography.body)
                .focused($inputFocused)
                .onSubmit { selectCurrent() }
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

    private var filtered: [FuzzyFileFilter.Match] {
        FuzzyFileFilter.filter(query: query, candidates: FuzzyFileFilter.flatten(allFiles))
    }

    @ViewBuilder
    private var resultsList: some View {
        let matches = filtered
        if matches.isEmpty {
            EmptyStateHint(
                icon: query.isEmpty ? "doc.text.magnifyingglass" : "questionmark.folder",
                title: query.isEmpty ? "검색어를 입력하세요" : "매칭 파일이 없어요",
                message: query.isEmpty
                    ? "파일 이름의 일부를 입력하면 fuzzy 검색해요. ↑↓ 화살표 + Enter로 이동."
                    : "‘\(query)’와 매칭되는 파일이 없어요. 자동 제외 폴더 (.git/.build 등)는 검색되지 않아요."
            )
            .frame(maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(Array(matches.prefix(50).enumerated()), id: \.element.path) { idx, match in
                            FileMatchRow(
                                match: match,
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
        onSelect(matches[selectedIndex].path)
    }

}

private struct FileMatchRow: View {
    let match: FuzzyFileFilter.Match
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Color.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(match.name)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Color.text)
                    Text(match.path)
                        .font(Theme.Typography.monoSmall)
                        .foregroundStyle(Theme.Color.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
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
