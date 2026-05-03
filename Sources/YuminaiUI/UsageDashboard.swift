import SwiftUI
import YuminaiCore

// MARK: - Public API

/// **ADR-075** — 사용량 대시보드 (compact / detailed 두 모드).
///
/// ## 설계 원칙 (ADR-075)
/// 1. **스크롤 없이 fit**: compact 모드는 작은 sheet (480×380), detailed 모드는 큰 sheet (760×680).
///    두 모드 모두 큰 화면에서는 스크롤 indicator 안 보임.
/// 2. **Agent + Model 필터**: detailed 모드에서 Claude/Codex × Haiku/Sonnet/Opus 조합 선택.
/// 3. **자세히 보기 분리**: 첫 진입은 compact (필수 정보만), 사용자가 "자세히 보기" 클릭 시 detailed.
/// 4. **점진 공개 패턴** (Progressive Disclosure, NN/g): 정보 과부하 회피.
public struct UsageDashboard: View {
    public let currentSessionUsage: UsageStats
    public let allTimeUsage: UsageStats
    public let activeAgent: AgentKind
    public let activeModel: ClaudeModel
    public let costSnapshot: CostTracker.Snapshot
    public let externalTurnCount: Int
    public let externalTurnCostUSD: Double
    public let cumulativeCacheHitRatio: Double
    public let totalCacheReadTokens: Int
    public let totalCacheCreationTokens: Int
    public let workspaceName: String?
    public let onClose: () -> Void

    @State private var viewMode: DashboardViewMode = .compact
    @State private var filterAgent: AgentFilter = .all
    @State private var filterModel: ModelFilter = .all

    public init(
        currentSessionUsage: UsageStats,
        allTimeUsage: UsageStats,
        activeAgent: AgentKind = .claude,
        activeModel: ClaudeModel,
        costSnapshot: CostTracker.Snapshot = CostTracker.Snapshot(main: 0, decomposition: 0, rehearsal: 0, routing: 0, parallel: 0),
        externalTurnCount: Int = 0,
        externalTurnCostUSD: Double = 0,
        cumulativeCacheHitRatio: Double = 0,
        totalCacheReadTokens: Int = 0,
        totalCacheCreationTokens: Int = 0,
        workspaceName: String? = nil,
        onClose: @escaping () -> Void
    ) {
        self.currentSessionUsage = currentSessionUsage
        self.allTimeUsage = allTimeUsage
        self.activeAgent = activeAgent
        self.activeModel = activeModel
        self.costSnapshot = costSnapshot
        self.externalTurnCount = externalTurnCount
        self.externalTurnCostUSD = externalTurnCostUSD
        self.cumulativeCacheHitRatio = cumulativeCacheHitRatio
        self.totalCacheReadTokens = totalCacheReadTokens
        self.totalCacheCreationTokens = totalCacheCreationTokens
        self.workspaceName = workspaceName
        self.onClose = onClose
    }

    public var body: some View {
        // ADR-075 — 모드별 다른 sheet 크기 (compact / detailed).
        // YuminaiSheet의 동적 sizing으로 큰 화면에선 fit, 작은 화면에선 자동 축소.
        YuminaiSheet(
            width: viewMode == .compact ? 520 : 760,
            height: viewMode == .compact ? 400 : 680
        ) {
            content
                .animation(.easeInOut(duration: 0.2), value: viewMode)
        } footer: {
            footerBar
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewMode {
        case .compact:
            CompactDashboardView(
                currentSessionUsage: currentSessionUsage,
                activeAgent: activeAgent,
                activeModel: activeModel,
                workspaceName: workspaceName,
                cumulativeCacheHitRatio: cumulativeCacheHitRatio
            )
        case .detailed:
            DetailedDashboardView(
                currentSessionUsage: currentSessionUsage,
                allTimeUsage: allTimeUsage,
                activeAgent: activeAgent,
                activeModel: activeModel,
                costSnapshot: costSnapshot,
                externalTurnCount: externalTurnCount,
                externalTurnCostUSD: externalTurnCostUSD,
                cumulativeCacheHitRatio: cumulativeCacheHitRatio,
                totalCacheReadTokens: totalCacheReadTokens,
                totalCacheCreationTokens: totalCacheCreationTokens,
                workspaceName: workspaceName,
                filterAgent: $filterAgent,
                filterModel: $filterModel
            )
        }
    }

    private var footerBar: some View {
        HStack(spacing: Theme.Spacing.md) {
            FlatButton(
                viewMode == .compact ? "자세히 보기" : "간단히 보기",
                icon: viewMode == .compact ? "rectangle.expand.vertical" : "rectangle.compress.vertical",
                variant: .secondary
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewMode = (viewMode == .compact) ? .detailed : .compact
                }
            }
            .accessibilityHint(viewMode == .compact ? "모든 사용 통계를 보여줍니다" : "핵심 정보만 보여줍니다")

            Spacer()

            FlatButton("닫기", variant: .primary, action: onClose)
                .keyboardShortcut(.escape, modifiers: [])
        }
    }
}

/// **ADR-075** — 사용량 대시보드 표시 모드.
public enum DashboardViewMode: String, Sendable, CaseIterable, Hashable {
    /// 핵심 정보만 (한 화면 fit, 스크롤 없음).
    case compact
    /// 모든 통계 + 필터 (큰 sheet).
    case detailed
}

/// **ADR-075** — Agent 필터 옵션.
public enum AgentFilter: String, Sendable, CaseIterable, Hashable, Identifiable {
    case all = "전체"
    case claude = "Claude"
    case codex = "Codex"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .all: return "square.stack"
        case .claude: return "sparkles"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

/// **ADR-075** — Model 필터 옵션.
public enum ModelFilter: String, Sendable, CaseIterable, Hashable, Identifiable {
    case all = "전체"
    case haiku = "Haiku"
    case sonnet = "Sonnet"
    case opus = "Opus"

    public var id: String { rawValue }

    public var subtitle: String {
        switch self {
        case .all: return "모든 모델"
        case .haiku: return "빠름·저비용"
        case .sonnet: return "균형"
        case .opus: return "최고 성능"
        }
    }
}

// MARK: - Compact view (default — 한 화면 fit)

/// **ADR-075** — 핵심 정보만 보여주는 compact view.
///
/// 디자인 원칙 (Apple HIG + NN/g Progressive Disclosure):
/// - Hero stat: 이번 세션 비용 (가장 큰 시각적 무게)
/// - Mini stats: 4개 핵심 지표 (메시지/입력/출력/캐시 hit)
/// - Context gauge: 컨텍스트 사용률 (잔여량 직관)
/// - 모델/에이전트/워크스페이스 정보 (footer style)
struct CompactDashboardView: View {
    let currentSessionUsage: UsageStats
    let activeAgent: AgentKind
    let activeModel: ClaudeModel
    let workspaceName: String?
    let cumulativeCacheHitRatio: Double

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            header
            heroCost
            miniStats
            contextSection
            Spacer(minLength: 0)
            modelInfo
        }
        .padding(Theme.Spacing.xl)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("이번 세션 사용량")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.text)
                Text("핵심 정보 요약")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
        }
    }

    private var heroCost: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("이번 세션 비용")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
                .textCase(.uppercase)
                .tracking(0.6)
            Text(String(format: "$%.4f", currentSessionUsage.costUSD))
                .font(.system(size: 36, weight: .semibold, design: .monospaced))
                .foregroundStyle(currentSessionUsage.costUSD > 0 ? Theme.Color.accent : Theme.Color.textSecondary)
                .accessibilityLabel("이번 세션 비용 \(String(format: "%.4f", currentSessionUsage.costUSD)) 달러")
        }
    }

    private var miniStats: some View {
        HStack(spacing: Theme.Spacing.lg) {
            MiniStatBox(label: "메시지", value: "\(currentSessionUsage.messageCount)")
            MiniStatBox(label: "입력 토큰", value: currentSessionUsage.inputTokens.formattedShort)
            MiniStatBox(label: "출력 토큰", value: currentSessionUsage.outputTokens.formattedShort)
            MiniStatBox(
                label: "캐시 적중률",
                value: "\(Int(cumulativeCacheHitRatio * 100))%",
                color: cacheColor
            )
            Spacer()
        }
    }

    private var cacheColor: Color {
        if cumulativeCacheHitRatio > 0.5 { return Theme.Color.success }
        if cumulativeCacheHitRatio > 0.2 { return Theme.Color.warning }
        return Theme.Color.textSecondary
    }

    private var contextSection: some View {
        ContextRow(usage: currentSessionUsage, model: activeModel)
    }

    private var modelInfo: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: activeAgent.icon)
                .font(.system(size: 11))
                .foregroundStyle(Theme.Color.accent)
                .accessibilityHidden(true)
            Text(activeAgent.displayName)
                .font(Theme.Typography.small.weight(.medium))
                .foregroundStyle(Theme.Color.text)
            Text("·")
                .foregroundStyle(Theme.Color.textTertiary)
            Text("\(activeModel.displayName) (\(activeModel.subtitle))")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
            if let workspaceName {
                Text("·")
                    .foregroundStyle(Theme.Color.textTertiary)
                Image(systemName: "folder")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Color.textTertiary)
                    .accessibilityHidden(true)
                Text(workspaceName)
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }
}

struct MiniStatBox: View {
    let label: String
    let value: String
    var color: Color = Theme.Color.text

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
                .textCase(.uppercase)
                .tracking(0.6)
            Text(value)
                .font(Theme.Typography.monoStat)
                .foregroundStyle(color)
        }
        .frame(minWidth: 80, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }
}

// MARK: - Detailed view (자세히 보기)

/// **ADR-075** — 모든 정보를 보여주는 detailed view.
struct DetailedDashboardView: View {
    let currentSessionUsage: UsageStats
    let allTimeUsage: UsageStats
    let activeAgent: AgentKind
    let activeModel: ClaudeModel
    let costSnapshot: CostTracker.Snapshot
    let externalTurnCount: Int
    let externalTurnCostUSD: Double
    let cumulativeCacheHitRatio: Double
    let totalCacheReadTokens: Int
    let totalCacheCreationTokens: Int
    let workspaceName: String?
    @Binding var filterAgent: AgentFilter
    @Binding var filterModel: ModelFilter

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            header
            filterBar
            Divider()
            // 큰 화면에서는 자연스럽게 fit, 작은 화면에서만 스크롤 indicator
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    sessionSection
                    cumulativeSection
                    if costSnapshot.total > 0 {
                        costBucketsSection
                    }
                    if totalCacheReadTokens > 0 || totalCacheCreationTokens > 0 {
                        cacheSection
                    }
                    if externalTurnCount > 0 {
                        externalTurnSection
                    }
                    pricingSection
                }
                .padding(.bottom, Theme.Spacing.md)
            }
            .scrollContentBackground(.hidden)
        }
        .padding(Theme.Spacing.xl)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("자세한 사용량")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.text)
                Text("이번 세션 + 누적 + 분리 비용")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: activeAgent.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Color.accent)
                    .accessibilityHidden(true)
                Text(activeAgent.displayName)
                    .font(Theme.Typography.monoSmall)
                    .foregroundStyle(Theme.Color.text)
                Text("·")
                    .foregroundStyle(Theme.Color.textTertiary)
                Text(activeModel.displayName)
                    .font(Theme.Typography.monoSmall)
                    .foregroundStyle(Theme.Color.text)
            }
        }
    }

    /// **ADR-075 Phase 3** — Agent + Model 필터.
    /// 현재는 표시만 (per-pair breakdown 데이터는 향후 ADR로 확장).
    /// UI는 미리 마련하여 추후 데이터 연결 시 즉시 활용 가능.
    private var filterBar: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text("에이전트")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .textCase(.uppercase)
                Picker("에이전트", selection: $filterAgent) {
                    ForEach(AgentFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                .accessibilityLabel("에이전트 필터")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("모델")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .textCase(.uppercase)
                Picker("모델", selection: $filterModel) {
                    ForEach(ModelFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("모델 필터")
            }
            Spacer()
        }
    }

    private var sessionSection: some View {
        FlatSection("이번 세션") {
            UsageGrid(usage: currentSessionUsage, model: activeModel)
        }
    }

    private var cumulativeSection: some View {
        FlatSection("앱 실행 후 누적") {
            UsageGrid(usage: allTimeUsage, model: activeModel)
        }
    }

    private var costBucketsSection: some View {
        FlatSection("Cost 분리 (격리 호출별)", footer: "ADR-053/054/055 — Decomposition/Rehearsal/Parallel/Routing 격리 호출 비용") {
            CostBucketsHistogram(snapshot: costSnapshot)
        }
    }

    private var cacheSection: some View {
        FlatSection("Cache 효과 (Anthropic prompt cache)") {
            CacheHitDashboard(
                ratio: cumulativeCacheHitRatio,
                readTokens: totalCacheReadTokens,
                creationTokens: totalCacheCreationTokens
            )
        }
    }

    private var externalTurnSection: some View {
        FlatSection("외부 turn (텔레그램)") {
            ExternalTurnSummary(count: externalTurnCount, totalCostUSD: externalTurnCostUSD)
        }
    }

    private var pricingSection: some View {
        FlatSection("모델 가격 비교", footer: "Anthropic 공식 가격 (1M tokens, USD)") {
            // 모든 ClaudeModel을 비교 표 형식
            ModelPricingTable(activeModel: activeModel)
        }
    }
}

// MARK: - Shared subviews

struct UsageGrid: View {
    let usage: UsageStats
    let model: ClaudeModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.xl) {
                StatBox(label: "메시지", value: "\(usage.messageCount)")
                StatBox(label: "입력", value: usage.inputTokens.formattedShort)
                StatBox(label: "출력", value: usage.outputTokens.formattedShort)
                StatBox(label: "캐시 R", value: usage.cacheReadTokens.formattedShort, color: Theme.Color.success)
                StatBox(label: "캐시 W", value: usage.cacheCreationTokens.formattedShort, color: Theme.Color.warning)
                StatBox(label: "비용", value: String(format: "$%.4f", usage.costUSD), color: Theme.Color.accent)
            }
            ContextRow(usage: usage, model: model)
        }
    }
}

struct StatBox: View {
    let label: String
    let value: String
    var color: SwiftUI.Color = Theme.Color.text

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
                .textCase(.uppercase)
                .tracking(0.6)
            Text(value)
                .font(Theme.Typography.monoStat)
                .foregroundStyle(color)
        }
        .frame(minWidth: 64, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }
}

struct ContextRow: View {
    let usage: UsageStats
    let model: ClaudeModel

    var body: some View {
        let ratio = usage.contextUsage(maxTokens: model.contextWindowTokens)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("컨텍스트")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Spacer()
                Text(String(format: "%.1f%% / %@", ratio * 100, model.contextWindowTokens.formattedShort))
                    .font(Theme.Typography.monoSmall)
                    .foregroundStyle(Theme.Color.text)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.Color.borderSubtle)
                    Rectangle()
                        .fill(barColor(ratio))
                        .frame(width: max(2, geo.size.width * ratio))
                }
            }
            .frame(height: 6)
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("컨텍스트 사용률 \(Int(ratio * 100)) 퍼센트")
    }

    private func barColor(_ ratio: Double) -> SwiftUI.Color {
        switch ratio {
        case ..<0.5: return Theme.Color.success
        case ..<0.75: return Theme.Color.warning
        default: return Theme.Color.danger
        }
    }
}

/// **ADR-075** — 모든 ClaudeModel 가격을 표 형식 비교 (활성 모델 강조).
struct ModelPricingTable: View {
    let activeModel: ClaudeModel

    var body: some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: Theme.Spacing.md) {
                Text("모델").frame(maxWidth: .infinity, alignment: .leading)
                Text("입력 / 1M").frame(width: 90, alignment: .trailing)
                Text("출력 / 1M").frame(width: 90, alignment: .trailing)
                Text("컨텍스트").frame(width: 80, alignment: .trailing)
            }
            .font(Theme.Typography.micro)
            .foregroundStyle(Theme.Color.textTertiary)
            .textCase(.uppercase)
            .padding(.bottom, 4)
            Divider()
            // Rows
            ForEach(ClaudeModel.allCases, id: \.self) { model in
                pricingRow(model: model, isActive: model == activeModel)
                if model != ClaudeModel.allCases.last {
                    Divider().opacity(0.5)
                }
            }
        }
    }

    private func pricingRow(model: ClaudeModel, isActive: Bool) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            HStack(spacing: 6) {
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Color.accent)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.displayName)
                        .font(Theme.Typography.body.weight(isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? Theme.Color.accent : Theme.Color.text)
                    Text(model.subtitle)
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(String(format: "$%.2f", model.inputPricePerMillion))
                .font(Theme.Typography.monoSmall)
                .foregroundStyle(Theme.Color.text)
                .frame(width: 90, alignment: .trailing)
            Text(String(format: "$%.2f", model.outputPricePerMillion))
                .font(Theme.Typography.monoSmall)
                .foregroundStyle(Theme.Color.text)
                .frame(width: 90, alignment: .trailing)
            Text(model.contextWindowTokens.formattedShort)
                .font(Theme.Typography.monoSmall)
                .foregroundStyle(Theme.Color.textSecondary)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.vertical, Theme.Spacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.displayName)\(isActive ? ", 현재 사용 중" : "")")
        .accessibilityValue("입력 \(String(format: "%.2f", model.inputPricePerMillion))달러, 출력 \(String(format: "%.2f", model.outputPricePerMillion))달러")
    }
}

// MARK: - ADR-055 #6 — Cost buckets histogram (재사용)

struct CostBucketsHistogram: View {
    let snapshot: CostTracker.Snapshot

    private var maxValue: Double {
        max(snapshot.main, snapshot.decomposition, snapshot.rehearsal, snapshot.parallel, snapshot.routing, 0.0001)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            bucketRow(label: "메인 대화", value: snapshot.main, color: .blue, hint: "사용자 conversation")
            bucketRow(label: "분해", value: snapshot.decomposition, color: .indigo, hint: "/decompose 격리 호출")
            bucketRow(label: "재실행", value: snapshot.rehearsal, color: .orange, hint: "다른 모델로 검증")
            bucketRow(label: "병렬", value: snapshot.parallel, color: .purple, hint: "두 번째 pane 동시 실행")
            bucketRow(label: "라우팅", value: snapshot.routing, color: .gray, hint: "LLM-based 분류 (현재 0)")
            Divider().padding(.vertical, 2)
            HStack {
                Text("합계")
                    .font(Theme.Typography.body.weight(.semibold))
                    .foregroundStyle(Theme.Color.text)
                Spacer()
                Text(String(format: "$%.4f", snapshot.total))
                    .font(Theme.Typography.monoSmall.weight(.semibold))
                    .foregroundStyle(Theme.Color.accent)
            }
        }
    }

    private func bucketRow(label: String, value: Double, color: Color, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(label)
                    .font(Theme.Typography.small.weight(.medium))
                    .foregroundStyle(Theme.Color.text)
                Text(hint)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                Spacer()
                Text(String(format: "$%.4f", value))
                    .font(Theme.Typography.monoSmall)
                    .foregroundStyle(Theme.Color.text)
            }
            GeometryReader { geo in
                let width = geo.size.width * CGFloat(value / maxValue)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.Color.surface)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.6))
                        .frame(width: max(width, 2))
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(String(format: "%.4f", value))달러")
    }
}

/// **ADR-059 Phase 1** — Anthropic prompt cache 효과 dashboard.
struct CacheHitDashboard: View {
    let ratio: Double
    let readTokens: Int
    let creationTokens: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                statBlock(label: "적중률", value: "\(Int(ratio * 100))%", color: ratio > 0.5 ? .green : (ratio > 0.2 ? .yellow : .orange))
                statBlock(label: "읽기 토큰", value: readTokens.formattedShort, color: .blue)
                statBlock(label: "생성 토큰", value: creationTokens.formattedShort, color: .indigo)
                Spacer()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.Color.surface)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(
                            colors: [.green.opacity(0.6), .blue.opacity(0.6)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: geo.size.width * ratio)
                }
            }
            .frame(height: 8)
            Text(ratio > 0.5 ? "✓ 효율적 — ProjectProfile 안정화 효과" : (ratio > 0.2 ? "보통 — 더 많은 격리 호출에서 cache hit 기대" : "낮음 — 첫 호출 또는 5분 TTL 만료 후"))
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
        }
    }

    private func statBlock(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
                .textCase(.uppercase)
                .tracking(0.6)
            Text(value)
                .font(Theme.Typography.title)
                .foregroundStyle(color)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }
}

/// **ADR-055 #6** — 외부 turn 카운트 + 누적 cost 요약 view.
struct ExternalTurnSummary: View {
    let count: Int
    let totalCostUSD: Double

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("외부 turn 횟수")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .textCase(.uppercase)
                Text("\(count)")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.text)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("외부 turn 누적 비용")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .textCase(.uppercase)
                Text(String(format: "$%.4f", totalCostUSD))
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.accent)
            }
            Spacer()
        }
    }
}
