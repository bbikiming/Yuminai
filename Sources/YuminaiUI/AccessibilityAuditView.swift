import SwiftUI
import YuminaiCore

/// **ADR-072 Phase 2** — Theme.Color 모든 조합의 WCAG 2.2 contrast 감사 패널.
///
/// 근거 자료:
/// - W3C WCAG 2.2 (https://www.w3.org/TR/WCAG22/) — 공식 권고 (2023-10-05)
/// - SC 1.4.3 Contrast (Minimum) AA: normal 4.5:1, large 3:1
/// - SC 1.4.6 Contrast (Enhanced) AAA: normal 7:1, large 4.5:1
/// - SC 1.4.11 Non-text Contrast AA: UI components 3:1
/// - Apple HIG Color: WCAG 2.x 권고 채택
///
/// UI/UX 관점:
/// - 색 대비 검증은 디자인 시스템 일관성 + 접근성 두 마리 토끼
/// - 본 모듈은 모든 Theme.Color 조합을 자동으로 검사 → 디자이너가 변경 시 즉시 피드백
/// - filter (AA 미충족만 / AAA 미충족만 / 전체)로 우선순위 검토 가능
public struct AccessibilityAuditView: View {
    @State private var filter: Filter = .aaFailures
    @State private var mode: ColorMode = .dark

    public init() {}

    public enum Filter: String, CaseIterable, Identifiable {
        case all = "전체"
        case aaFailures = "AA 미충족"
        case aaaFailures = "AAA 미충족"
        case allPass = "모두 통과"

        public var id: String { rawValue }
    }

    public enum ColorMode: String, CaseIterable, Identifiable {
        case dark = "다크"
        case light = "라이트"
        public var id: String { rawValue }
    }

    /// **감사 대상** — Theme.Color에서 실제 사용되는 조합.
    /// hex 값은 Theme.swift와 1:1 일치해야 함.
    static let pairs: [ThemeColorPair] = [
        // ── 본문 텍스트
        .init(id: "text-on-bg",
              foregroundName: "text", backgroundName: "bg",
              foregroundDark: 0xf0eeec, backgroundDark: 0x1a1817,
              foregroundLight: 0x1a1817, backgroundLight: 0xf6f3ee,
              usageContext: "메인 본문 (메시지, 채팅 등)"),
        .init(id: "text-on-surface",
              foregroundName: "text", backgroundName: "surface",
              foregroundDark: 0xf0eeec, backgroundDark: 0x211f1d,
              foregroundLight: 0x1a1817, backgroundLight: 0xfffefb,
              usageContext: "카드/패널 본문"),
        .init(id: "text-on-surfaceHi",
              foregroundName: "text", backgroundName: "surfaceHi",
              foregroundDark: 0xf0eeec, backgroundDark: 0x2a2724,
              foregroundLight: 0x1a1817, backgroundLight: 0xe8e4dd,
              usageContext: "버튼 hover, 강조 surface"),

        // ── 보조 텍스트
        .init(id: "textSecondary-on-bg",
              foregroundName: "textSecondary", backgroundName: "bg",
              foregroundDark: 0xa8a3a0, backgroundDark: 0x1a1817,
              foregroundLight: 0x5a5552, backgroundLight: 0xf6f3ee,
              usageContext: "보조 설명, footer 등"),
        .init(id: "textSecondary-on-surface",
              foregroundName: "textSecondary", backgroundName: "surface",
              foregroundDark: 0xa8a3a0, backgroundDark: 0x211f1d,
              foregroundLight: 0x5a5552, backgroundLight: 0xfffefb,
              usageContext: "카드 보조 캡션"),

        // ── 약한 텍스트 (ADR-072 Phase 2에서 brightening 후 AA pass)
        .init(id: "textTertiary-on-bg",
              foregroundName: "textTertiary", backgroundName: "bg",
              foregroundDark: 0x8e8884, backgroundDark: 0x1a1817,
              foregroundLight: 0x6b6663, backgroundLight: 0xf6f3ee,
              usageContext: "label, hint, micro 텍스트 — 보통 11pt"),
        .init(id: "textTertiary-on-surface",
              foregroundName: "textTertiary", backgroundName: "surface",
              foregroundDark: 0x8e8884, backgroundDark: 0x211f1d,
              foregroundLight: 0x6b6663, backgroundLight: 0xfffefb,
              usageContext: "stat 캡션 등"),

        // ── disabled
        .init(id: "textDisabled-on-bg",
              foregroundName: "textDisabled", backgroundName: "bg",
              foregroundDark: 0x5a5552, backgroundDark: 0x1a1817,
              foregroundLight: 0x9a948f, backgroundLight: 0xf6f3ee,
              usageContext: "비활성 버튼, disabled 항목"),

        // ── Accent (Brand)
        .init(id: "accent-on-bg",
              foregroundName: "accent", backgroundName: "bg",
              foregroundDark: 0x22C8E0, backgroundDark: 0x1a1817,
              foregroundLight: 0x22C8E0, backgroundLight: 0xf6f3ee,
              usageContext: "active state, link, streaming"),

        // ── 상태 색
        .init(id: "success-on-bg",
              foregroundName: "success", backgroundName: "bg",
              foregroundDark: 0x8fc999, backgroundDark: 0x1a1817,
              foregroundLight: 0x8fc999, backgroundLight: 0xf6f3ee,
              usageContext: "성공 indicator, diff plus"),
        .init(id: "warning-on-bg",
              foregroundName: "warning", backgroundName: "bg",
              foregroundDark: 0xd4b86a, backgroundDark: 0x1a1817,
              foregroundLight: 0xd4b86a, backgroundLight: 0xf6f3ee,
              usageContext: "경고 indicator"),
        .init(id: "danger-on-bg",
              foregroundName: "danger", backgroundName: "bg",
              foregroundDark: 0xd97373, backgroundDark: 0x1a1817,
              foregroundLight: 0xd97373, backgroundLight: 0xf6f3ee,
              usageContext: "에러, diff minus, 취소"),

        // ── Border (non-text, SC 1.4.11)
        .init(id: "border-on-bg",
              foregroundName: "border", backgroundName: "bg",
              foregroundDark: 0x3d3834, backgroundDark: 0x1a1817,
              foregroundLight: 0xc8c1b9, backgroundLight: 0xf6f3ee,
              usageContext: "구분선, 카드 테두리",
              isText: false),
        .init(id: "borderStrong-on-bg",
              foregroundName: "borderStrong", backgroundName: "bg",
              foregroundDark: 0x504a44, backgroundDark: 0x1a1817,
              foregroundLight: 0xa8a098, backgroundLight: 0xf6f3ee,
              usageContext: "focus border, 강조 테두리",
              isText: false)
    ]

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            header
            controls
            summary
            Divider()
            ScrollView {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(filteredPairs) { pair in
                        contrastRow(pair)
                    }
                }
                .padding(.bottom, Theme.Spacing.md)
            }
        }
        .padding(Theme.Spacing.md)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("색 대비 감사 (WCAG 2.2)")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Color.text)
            Text("W3C WCAG 2.2 SC 1.4.3 / 1.4.6 / 1.4.11 기반. AA: 본문 4.5:1 · 큰 텍스트 3:1 · UI 요소 3:1.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: 4) {
                Text("필터")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                Picker("필터", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("모드")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                Picker("모드", selection: $mode) {
                    ForEach(ColorMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 140)
            }
        }
    }

    // MARK: - Summary stats

    private var summary: some View {
        let total = Self.pairs.count
        let dark = Self.pairs.filter { $0.passesDarkAA() }.count
        let light = Self.pairs.filter { $0.passesLightAA() }.count
        return HStack(spacing: Theme.Spacing.lg) {
            statBlock("전체", "\(total)개", color: Theme.Color.text)
            statBlock("다크 AA 통과", "\(dark)/\(total)",
                      color: dark == total ? Theme.Color.success : Theme.Color.warning)
            statBlock("라이트 AA 통과", "\(light)/\(total)",
                      color: light == total ? Theme.Color.success : Theme.Color.warning)
            Spacer()
        }
    }

    private func statBlock(_ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
            Text(value)
                .font(Theme.Typography.monoStat)
                .foregroundStyle(color)
        }
    }

    // MARK: - Filtered list

    private var filteredPairs: [ThemeColorPair] {
        switch filter {
        case .all: return Self.pairs
        case .aaFailures:
            return Self.pairs.filter { pair in
                let result = (mode == .dark) ? pair.darkResult() : pair.lightResult()
                return result.ratio < pair.aaThreshold
            }
        case .aaaFailures:
            return Self.pairs.filter { pair in
                let result = (mode == .dark) ? pair.darkResult() : pair.lightResult()
                return result.ratio < pair.aaaThreshold
            }
        case .allPass:
            return Self.pairs.filter { pair in
                let result = (mode == .dark) ? pair.darkResult() : pair.lightResult()
                return result.ratio >= pair.aaThreshold
            }
        }
    }

    // MARK: - Contrast row

    @ViewBuilder
    private func contrastRow(_ pair: ThemeColorPair) -> some View {
        let result = (mode == .dark) ? pair.darkResult() : pair.lightResult()
        let fg = (mode == .dark) ? pair.foregroundDark : pair.foregroundLight
        let bg = (mode == .dark) ? pair.backgroundDark : pair.backgroundLight
        let passesAA = result.ratio >= pair.aaThreshold

        HStack(spacing: Theme.Spacing.md) {
            // Color preview swatch
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(Color(rgb: bg))
                    .frame(width: 80, height: 56)
                Text("Aa")
                    .font(.system(size: 22, weight: .semibold, design: .default))
                    .foregroundStyle(Color(rgb: fg))
            }
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .stroke(Theme.Color.borderSubtle, lineWidth: 1)
            )

            // Pair info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(pair.foregroundName)")
                        .font(Theme.Typography.bodyEmphasis)
                        .foregroundStyle(Theme.Color.text)
                    Text("on")
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textTertiary)
                    Text("\(pair.backgroundName)")
                        .font(Theme.Typography.bodyEmphasis)
                        .foregroundStyle(Theme.Color.text)
                    if !pair.isText {
                        Text("UI 요소")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Theme.Color.surfaceHi)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                Text(pair.usageContext)
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            // Contrast ratio + badges
            VStack(alignment: .trailing, spacing: 4) {
                Text(result.displayRatio)
                    .font(Theme.Typography.monoStat)
                    .foregroundStyle(passesAA ? Theme.Color.success : Theme.Color.danger)
                HStack(spacing: 4) {
                    badge("AA", pass: result.ratio >= pair.aaThreshold)
                    badge("AAA", pass: result.ratio >= pair.aaaThreshold)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(passesAA ? Color.clear : Theme.Color.danger.opacity(0.4), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(pair.foregroundName)을 \(pair.backgroundName) 위에 표시")
        .accessibilityValue("대비 \(result.displayRatio), \(result.worstLevel)")
    }

    private func badge(_ text: String, pass: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: pass ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 9))
                .foregroundStyle(pass ? Theme.Color.success : Theme.Color.danger)
            Text(text)
                .font(Theme.Typography.micro)
                .foregroundStyle(pass ? Theme.Color.success : Theme.Color.danger)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background((pass ? Theme.Color.success : Theme.Color.danger).opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
