import SwiftUI
import YuminaiCore

/// **ADR-056 Phase 5 + ADR-070 Phase 2** — Settings 패널: 자동 모델 선택 학습.
///
/// **변경 (ADR-070)**:
/// - 다른 설정 탭과 동일한 `Section` + `LabeledContent` 패턴으로 정렬 통일
/// - 한국어 친화 UX 라이팅 (Apple HIG / NN/g Heuristic #2 / Microsoft Voice "Be human")
///   - "Muted Keywords" → "차단된 단어"
///   - "Cancel 학습 진행" → "사용자 교정 학습 중인 단어"
///   - "TaskKind" → "작업 유형"
///   - "binary 3회 OR weight ratio ≥ 0.5" → "3회 취소 또는 50% 이상 취소율"
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

    /// 작업 유형 한글 라벨 — UX 라이팅 친화 (raw key는 내부 ID).
    private static let kinds: [(id: String, label: String)] = [
        ("codeGeneration", "코드 생성"),
        ("codeReview", "코드 리뷰"),
        ("debugging", "디버깅"),
        ("planning", "계획 수립"),
        ("longContextSearch", "긴 문맥 검색"),
        ("generalChat", "일반 대화")
    ]

    /// raw kind id → 한글 라벨 lookup.
    private static func label(for kindId: String) -> String {
        kinds.first(where: { $0.id == kindId })?.label ?? kindId
    }

    public var body: some View {
        // ADR-070 Phase 2 — 다른 설정 탭과 동일한 VStack을 쓰지 않고,
        // 호출자(SettingsView)가 Form/Section으로 감싸도록 변경.
        // 이 panel은 단순히 Section 바디를 제공.
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            mutedSection
            cancelCountsSection
            customKeywordsSection
        }
    }

    // MARK: - 차단된 단어 (이전 "Muted Keywords")

    private var mutedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("차단된 단어")
                    .font(Theme.Typography.body.weight(.semibold))
                    .foregroundStyle(Theme.Color.text)
                HelpHint(
                    "이 단어들은 자동 모델 선택에서 제외됩니다. 사용자가 자동 전환을 \(RoutingLearningStore.muteThreshold)회 취소하면 자동으로 추가됩니다. ✕ 버튼으로 다시 활성화할 수 있어요.",
                    title: "차단된 단어란?",
                    placement: .trailing
                )
            }
            if snapshot.mutedKeywords.isEmpty {
                Text("아직 차단된 단어가 없어요. 같은 단어에서 \(RoutingLearningStore.muteThreshold)회 취소하면 자동으로 추가됩니다.")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 6)], alignment: .leading, spacing: 6) {
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
            .help("차단 해제 (자동 모델 선택에 다시 사용)")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Theme.Color.warningStrong.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - 학습 진행 중인 단어 (이전 "Cancel 학습 진행")

    private var cancelCountsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("학습 중인 단어")
                    .font(Theme.Typography.body.weight(.semibold))
                    .foregroundStyle(Theme.Color.text)
                HelpHint(
                    "사용자가 자동 모델 선택을 취소한 단어들의 학습 진행 상황입니다. \(RoutingLearningStore.muteThreshold)회 취소되거나 취소율이 \(Int(RoutingLearningStore.muteRatioThreshold * 100))% 이상이면 자동으로 차단됩니다.",
                    title: "학습 중인 단어란?",
                    placement: .trailing
                )
            }
            let nonMuted = snapshot.cancelCounts.filter { !snapshot.mutedKeywords.contains($0.key) }
            if nonMuted.isEmpty {
                Text("학습 중인 단어가 없어요.")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(nonMuted.sorted(by: { $0.value > $1.value }), id: \.key) { item in
                        learningRow(keyword: item.key, cancelCount: item.value)
                    }
                }
            }
        }
    }

    /// **ADR-059 Phase 3** — keyword 학습 row: 취소 횟수 + 취소율 bar.
    private func learningRow(keyword: String, cancelCount: Int) -> some View {
        let useCount = snapshot.useCounts[keyword] ?? 0
        let ratio = snapshot.cancelRatio(keyword)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("‘\(keyword)’")
                    .font(Theme.Typography.monoSmall)
                    .foregroundStyle(Theme.Color.text)
                    .frame(width: 100, alignment: .leading)
                ProgressView(value: Double(min(cancelCount, RoutingLearningStore.muteThreshold)), total: Double(RoutingLearningStore.muteThreshold))
                    .frame(maxWidth: .infinity)
                Text("\(cancelCount) / \(RoutingLearningStore.muteThreshold)회")
                    .font(Theme.Typography.monoSmall)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .frame(width: 60, alignment: .trailing)
            }
            if let r = ratio {
                HStack(spacing: 8) {
                    Text("취소율")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                        .frame(width: 100, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Theme.Color.surface)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(r >= RoutingLearningStore.muteRatioThreshold ? Theme.Color.warningStrong : Theme.Color.infoBlue.opacity(0.6))
                                .frame(width: geo.size.width * r)
                            // muteRatioThreshold 위치 표시 (점선)
                            Rectangle()
                                .fill(Theme.Color.gitRemoved.opacity(0.4))
                                .frame(width: 1)
                                .offset(x: geo.size.width * RoutingLearningStore.muteRatioThreshold)
                        }
                    }
                    .frame(height: 4)
                    Text("\(Int(r * 100))% (\(cancelCount)/\(useCount))")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(r >= RoutingLearningStore.muteRatioThreshold ? Theme.Color.warningStrong : Theme.Color.textTertiary)
                        .frame(width: 80, alignment: .trailing)
                }
            } else if useCount > 0 {
                Text("샘플 부족 — \(useCount)/\(RoutingLearningStore.minSamplesForRatio)회 사용 후 취소율 적용")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .padding(.leading, 100 + 8)
            }
        }
    }

    // MARK: - 사용자 정의 단어 (이전 "Custom Keywords")

    private var customKeywordsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("사용자 정의 단어")
                    .font(Theme.Typography.body.weight(.semibold))
                    .foregroundStyle(Theme.Color.text)
                HelpHint(
                    "특정 단어가 입력되면 지정한 작업 유형으로 자동 분류됩니다. 기본 단어보다 우선순위가 높습니다. 예: ‘작성’ → 코드 생성으로 매핑.",
                    title: "사용자 정의 단어란?",
                    placement: .trailing
                )
            }

            // ADR-070 Phase 2 — LabeledContent 패턴으로 라벨 정렬 통일
            HStack(spacing: 8) {
                Picker("작업 유형", selection: $selectedKind) {
                    ForEach(Self.kinds, id: \.id) { kind in
                        Text(kind.label).tag(kind.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 140)

                TextField("새 단어 (예: 작성, 점검)", text: $newKeyword)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)

                Button("추가") {
                    let kw = newKeyword.trimmingCharacters(in: .whitespaces)
                    guard !kw.isEmpty else { return }
                    onAddCustom(kw, selectedKind)
                    newKeyword = ""
                }
                .disabled(newKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if snapshot.customKeywords.isEmpty {
                Text("등록된 사용자 정의 단어가 없어요.")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(snapshot.customKeywords.keys.sorted(), id: \.self) { kind in
                        if let kws = snapshot.customKeywords[kind], !kws.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Self.label(for: kind))
                                    .font(Theme.Typography.micro.weight(.semibold))
                                    .foregroundStyle(Theme.Color.textSecondary)
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 6)], alignment: .leading, spacing: 6) {
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
