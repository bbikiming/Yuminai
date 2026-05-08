import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-132** — 자동 실행 설정 카드.
///
/// `AutoRunControlSheet` 내부 또는 전역 설정 탭에서 사용.
///
/// ## 친화 언어 (ADR-101)
/// - Max turns → 최대 진행 횟수
/// - Budget → 예산
/// - Duration → 지속 시간
/// - Stop keywords → 종료 신호 단어
/// - Auto-approve permissions → 권한 자동 승인
/// - Harness rules auto-load → 워크스페이스 규칙 자동 적용
public struct AutoRunSettingsView: View {

    @Binding public var config: AutoRunConfig
    @State private var stopKeywordsText: String = ""

    public init(config: Binding<AutoRunConfig>) {
        self._config = config
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            sectionHeader("기본 제한")
            basicLimitsSection

            FlatHDivider()

            sectionHeader("종료 신호")
            stopKeywordsSection

            FlatHDivider()

            sectionHeader("권한 & 안전")
            safetySection

            FlatHDivider()

            sectionHeader("Harness & 알림")
            harnessSection
        }
        .onAppear {
            stopKeywordsText = config.stopKeywords.joined(separator: "\n")
        }
    }

    // MARK: - 기본 제한

    private var basicLimitsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // 최대 진행 횟수
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("최대 진행 횟수")
                        .font(Theme.Typography.label)
                    Spacer()
                    Text("\(config.maxTurns)회")
                        .font(Theme.Typography.monoSmall)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                Slider(
                    value: Binding(
                        get: { Double(config.maxTurns) },
                        set: { newVal in
                            var c = config
                            c.maxTurns = max(1, min(200, Int(newVal)))
                            config = c
                        }
                    ),
                    in: 10...100,
                    step: 5
                )
                .tint(.green)
                Text("hard cap: 200회")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
            }

            // 최대 예산
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("최대 예산")
                        .font(Theme.Typography.label)
                    Spacer()
                    Text("$\(String(format: "%.2f", config.maxBudgetUSD))")
                        .font(Theme.Typography.monoSmall)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                Slider(
                    value: Binding(
                        get: { config.maxBudgetUSD },
                        set: { newVal in
                            var c = config
                            c.maxBudgetUSD = newVal
                            config = c
                        }
                    ),
                    in: 1.0...10.0,
                    step: 0.5
                )
                .tint(.green)
            }

            // 최대 지속 시간
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("최대 지속 시간")
                        .font(Theme.Typography.label)
                    Spacer()
                    Text(formatDuration(config.maxDurationSeconds))
                        .font(Theme.Typography.monoSmall)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                Slider(
                    value: Binding(
                        get: { config.maxDurationSeconds / 60 },
                        set: { newVal in
                            var c = config
                            c.maxDurationSeconds = newVal * 60
                            config = c
                        }
                    ),
                    in: 5...240,
                    step: 5
                )
                .tint(.green)
                Text("최대 4시간 (hard cap)")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
            }

            // 에러 임계값
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("연속 오류 허용 횟수")
                        .font(Theme.Typography.label)
                    Spacer()
                    Text("\(config.errorThreshold)회")
                        .font(Theme.Typography.monoSmall)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                Slider(
                    value: Binding(
                        get: { Double(config.errorThreshold) },
                        set: { newVal in
                            var c = config
                            c.errorThreshold = max(1, Int(newVal))
                            config = c
                        }
                    ),
                    in: 1...10,
                    step: 1
                )
                .tint(.orange)
            }
        }
    }

    // MARK: - 종료 신호 단어

    private var stopKeywordsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("종료 신호 단어")
                .font(Theme.Typography.label)
            Text("한 줄에 하나씩 입력. 응답에 이 단어가 나오면 자동으로 종료됩니다.")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)

            TextEditor(text: $stopKeywordsText)
                .font(Theme.Typography.monoSmall)
                .frame(height: 80)
                .padding(Theme.Spacing.xs)
                .background(Theme.Color.surfaceHi)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .stroke(Theme.Color.borderSubtle, lineWidth: 0.5)
                )
                .onChange(of: stopKeywordsText) { newValue in
                    let keywords = newValue
                        .components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    var c = config
                    c.stopKeywords = keywords
                    config = c
                }
        }
    }

    // MARK: - 안전

    private var safetySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // HITL destructive guard
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Label("위험 명령 감지 후 일시정지", systemImage: "shield.fill")
                        .font(Theme.Typography.label)
                        .foregroundStyle(config.stopOnDestructive ? .green : Theme.Color.text)
                    Text("rm -rf, DROP TABLE 등 감지 시 일시정지 후 승인 대기 (권장: ON)")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { config.stopOnDestructive },
                    set: { newVal in
                        var c = config
                        c.stopOnDestructive = newVal
                        config = c
                    }
                ))
                .toggleStyle(.switch)
                .tint(.green)
            }
            .padding(Theme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(config.stopOnDestructive ? Theme.Color.gitAdded.opacity(0.06) : Theme.Color.danger.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .stroke(
                        config.stopOnDestructive ? Theme.Color.gitAdded.opacity(0.2) : Theme.Color.danger.opacity(0.3),
                        lineWidth: 0.5
                    )
            )

            if !config.stopOnDestructive {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.Color.danger)
                        .font(.system(size: 11))
                    Text("위험 명령 감지가 꺼져 있습니다. 데이터 손실 위험이 있습니다.")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.danger)
                }
            }

            // 권한 자동 승인
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("권한 자동 승인")
                        .font(Theme.Typography.label)
                    Text("HITL 승인 요청을 자동으로 허가 (위험 명령 제외)")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { config.autoApprovePermissions },
                    set: { newVal in
                        var c = config
                        c.autoApprovePermissions = newVal
                        config = c
                    }
                ))
                .toggleStyle(.switch)
                .tint(Theme.Color.accent)
            }

            if config.autoApprovePermissions {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Theme.Color.textTertiary)
                        .font(.system(size: 11))
                    Text("위험 명령은 항상 수동 승인이 필요합니다.")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
            }
        }
    }

    // MARK: - Harness + 알림

    private var harnessSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("워크스페이스 규칙 자동 적용")
                        .font(Theme.Typography.label)
                    Text(".harness/rules/*.md를 system prompt에 주입")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { config.autoLoadHarnessRules },
                    set: { newVal in
                        var c = config
                        c.autoLoadHarnessRules = newVal
                        config = c
                    }
                ))
                .toggleStyle(.switch)
                .tint(Theme.Color.accent)
            }

            HStack {
                Text("완료 알림")
                    .font(Theme.Typography.label)
                Spacer()
                Picker("", selection: Binding(
                    get: { config.notifyChannel },
                    set: { newVal in
                        var c = config
                        c.notifyChannel = newVal
                        config = c
                    }
                )) {
                    ForEach(AutoRunConfig.NotifyChannel.allCases, id: \.self) { ch in
                        Text(ch.displayName).tag(ch)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)
            }
        }
    }

    // MARK: - 헬퍼

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.bodyEmphasis)
            .foregroundStyle(Theme.Color.textSecondary)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds / 60)
        if mins >= 60 {
            return "\(mins / 60)시간 \(mins % 60)분"
        }
        return "\(mins)분"
    }
}
