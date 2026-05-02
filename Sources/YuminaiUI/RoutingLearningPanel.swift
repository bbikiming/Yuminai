import SwiftUI
import YuminaiCore

/// **ADR-056 Phase 5** — Settings에 표시할 Routing Learning panel.
///
/// muted keywords 표시 + unmute, 사용자 정의 keyword 추가/삭제, cancel count 시각화.
public struct RoutingLearningPanel: View {
    public let snapshot: RoutingLearningStore.Snapshot
    public let onUnmute: (String) -> Void
    public let onAddCustom: (_ keyword: String, _ taskKind: String) -> Void
    public let onRemoveCustom: (_ keyword: String, _ taskKind: String) -> Void

    public init(
        snapshot: RoutingLearningStore.Snapshot,
        onUnmute: @escaping (String) -> Void,
        onAddCustom: @escaping (String, String) -> Void,
        onRemoveCustom: @escaping (String, String) -> Void
    ) {
        self.snapshot = snapshot
        self.onUnmute = onUnmute
        self.onAddCustom = onAddCustom
        self.onRemoveCustom = onRemoveCustom
    }

    @State private var newKeyword: String = ""
    @State private var selectedKind: String = "codeGeneration"

    private static let kinds = ["codeGeneration", "codeReview", "debugging", "planning", "longContextSearch", "generalChat"]

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            mutedSection
            cancelCountsSection
            customKeywordsSection
        }
    }

    // MARK: - Muted

    private var mutedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Muted Keywords (자동 routing 제외)")
                .font(Theme.Typography.body.weight(.semibold))
                .foregroundStyle(Theme.Color.text)
            if snapshot.mutedKeywords.isEmpty {
                Text("(아직 자동 mute된 keyword 없음 — 같은 keyword에서 \(RoutingLearningStore.muteThreshold)회 cancel하면 자동 추가)")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 6)], spacing: 6) {
                    ForEach(snapshot.mutedKeywords.sorted(), id: \.self) { kw in
                        mutedChip(kw)
                    }
                }
            }
        }
    }

    private func mutedChip(_ keyword: String) -> some View {
        HStack(spacing: 4) {
            Text("‘\(keyword)’")
                .font(Theme.Typography.monoSmall)
                .foregroundStyle(Theme.Color.text)
            Button(action: { onUnmute(keyword) }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Unmute (다시 자동 routing 활성)")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Cancel counts (학습 진행)

    private var cancelCountsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cancel 학습 진행 (binary 3회 OR weight ratio ≥ 0.5)")
                .font(Theme.Typography.body.weight(.semibold))
                .foregroundStyle(Theme.Color.text)
            let nonMuted = snapshot.cancelCounts.filter { !snapshot.mutedKeywords.contains($0.key) }
            if nonMuted.isEmpty {
                Text("(cancel 진행 중인 keyword 없음)")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
            } else {
                ForEach(nonMuted.sorted(by: { $0.value > $1.value }), id: \.key) { item in
                    learningRow(keyword: item.key, cancelCount: item.value)
                }
            }
        }
    }

    /// **ADR-059 Phase 3** — keyword 학습 row: binary progress + weight ratio bar.
    private func learningRow(keyword: String, cancelCount: Int) -> some View {
        let useCount = snapshot.useCounts[keyword] ?? 0
        let ratio = snapshot.cancelRatio(keyword)
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("‘\(keyword)’")
                    .font(Theme.Typography.monoSmall)
                    .frame(width: 100, alignment: .leading)
                // Binary progress (3회까지)
                ProgressView(value: Double(min(cancelCount, RoutingLearningStore.muteThreshold)), total: Double(RoutingLearningStore.muteThreshold))
                    .frame(maxWidth: .infinity)
                Text("\(cancelCount) / \(RoutingLearningStore.muteThreshold)")
                    .font(Theme.Typography.monoSmall)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .frame(width: 50, alignment: .trailing)
            }
            // ADR-059 Phase 3 — weight ratio bar (충분한 sample 있을 때만)
            if let r = ratio {
                HStack(spacing: 6) {
                    Text("ratio")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                        .frame(width: 100, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Theme.Color.surface)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(r >= RoutingLearningStore.muteRatioThreshold ? Color.orange : Color.blue.opacity(0.6))
                                .frame(width: geo.size.width * r)
                            // 0.5 임계 표시 (점선)
                            Rectangle()
                                .fill(Color.red.opacity(0.4))
                                .frame(width: 1)
                                .offset(x: geo.size.width * RoutingLearningStore.muteRatioThreshold)
                        }
                    }
                    .frame(height: 4)
                    Text("\(Int(r * 100))% (\(cancelCount)/\(useCount))")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(r >= RoutingLearningStore.muteRatioThreshold ? Color.orange : Theme.Color.textTertiary)
                        .frame(width: 80, alignment: .trailing)
                }
            } else if useCount > 0 {
                Text("ratio: \(useCount)/\(RoutingLearningStore.minSamplesForRatio) sample 후 weight 적용")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .padding(.leading, 100)
            }
        }
    }

    // MARK: - Custom keywords

    private var customKeywordsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("사용자 정의 Keywords (TaskKind별)")
                .font(Theme.Typography.body.weight(.semibold))
                .foregroundStyle(Theme.Color.text)

            HStack {
                Picker("TaskKind", selection: $selectedKind) {
                    ForEach(Self.kinds, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .frame(width: 180)
                TextField("새 keyword (예: 작성)", text: $newKeyword)
                    .textFieldStyle(.roundedBorder)
                Button("추가") {
                    let kw = newKeyword.trimmingCharacters(in: .whitespaces)
                    guard !kw.isEmpty else { return }
                    onAddCustom(kw, selectedKind)
                    newKeyword = ""
                }
                .disabled(newKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if snapshot.customKeywords.isEmpty {
                Text("(custom keyword 없음)")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
            } else {
                ForEach(snapshot.customKeywords.keys.sorted(), id: \.self) { kind in
                    if let kws = snapshot.customKeywords[kind], !kws.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind)
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Color.textTertiary)
                                .textCase(.uppercase)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 6)], spacing: 6) {
                                ForEach(kws, id: \.self) { kw in
                                    customChip(kw, kind: kind)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func customChip(_ keyword: String, kind: String) -> some View {
        HStack(spacing: 4) {
            Text("‘\(keyword)’")
                .font(Theme.Typography.monoSmall)
                .foregroundStyle(Theme.Color.text)
            Button(action: { onRemoveCustom(keyword, kind) }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Theme.Color.accentMuted)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
