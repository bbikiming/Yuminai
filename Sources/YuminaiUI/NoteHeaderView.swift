import SwiftUI
import YuminaiObsidian

/// 노트 본문 위 헤더 — frontmatter title + tags + 메타.
public struct NoteHeaderView: View {
    public let note: Note

    public init(note: Note) {
        self.note = note
    }

    public var body: some View {
        if shouldShow {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if let title = displayTitle {
                    Text(title)
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Color.text)
                        .lineLimit(2)
                }

                if !tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            tagPill(tag)
                        }
                    }
                }

                if !otherMeta.isEmpty {
                    HStack(spacing: Theme.Spacing.lg) {
                        ForEach(otherMeta, id: \.0) { key, value in
                            HStack(spacing: 4) {
                                Text(key)
                                    .font(Theme.Typography.small)
                                    .foregroundStyle(Theme.Color.textTertiary)
                                Text(value)
                                    .font(Theme.Typography.small)
                                    .foregroundStyle(Theme.Color.textSecondary)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var shouldShow: Bool {
        displayTitle != nil || !tags.isEmpty || !otherMeta.isEmpty
    }

    private var displayTitle: String? {
        note.frontmatter["title"]
    }

    private var tags: [String] {
        guard let raw = note.frontmatter["tags"] else { return [] }
        // 두 형식 지원: `tags: a, b, c` 와 `tags: [a, b, c]`
        let cleaned = raw
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
        return cleaned
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var otherMeta: [(String, String)] {
        let reserved = Set(["title", "tags"])
        return note.frontmatter
            .filter { !reserved.contains($0.key) && !$0.value.isEmpty }
            .sorted { $0.key < $1.key }
    }

    private func tagPill(_ tag: String) -> some View {
        Text(tag)
            .font(Theme.Typography.micro)
            .foregroundStyle(Theme.Color.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Theme.Color.accentMuted)
            .clipShape(Capsule())
    }
}
