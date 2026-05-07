import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-133** — 명령 정책 매트릭스 편집 View.
///
/// AutoRunSettingsView 안의 [명령 정책 편집] 버튼으로 진입.
/// allow/deny 패턴 추가·삭제, 기본 패턴 확인, 정규식 검증을 제공한다.
///
/// ## 친화 언어 (ADR-101)
/// - allowList/allowPatterns → 자동 승인 명령
/// - denyPatterns → 차단 명령
/// - requireConfirmation → 확인 필요
public struct CommandPolicySettingsView: View {

    @Binding public var policy: CommandPolicyMatrix

    @State private var newAllowPattern: String = ""
    @State private var newDenyPattern: String = ""
    @State private var allowPatternError: String? = nil
    @State private var denyPatternError: String? = nil
    @State private var selectedSection: Section = .allow

    public init(policy: Binding<CommandPolicyMatrix>) {
        self._policy = policy
    }

    private enum Section: String, CaseIterable {
        case allow = "자동 승인"
        case deny = "차단"
        case preview = "정책 미리보기"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionPicker
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    switch selectedSection {
                    case .allow:
                        allowSection
                    case .deny:
                        denySection
                    case .preview:
                        previewSection
                    }
                }
                .padding(Theme.Spacing.lg)
            }
        }
    }

    // MARK: - 섹션 피커

    private var sectionPicker: some View {
        Picker("섹션", selection: $selectedSection) {
            ForEach(Section.allCases, id: \.self) { section in
                Text(section.rawValue).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
    }

    // MARK: - 자동 승인 섹션

    private var allowSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            // 안내
            infoCard(
                icon: "checkmark.circle.fill",
                color: Theme.Color.success,
                title: "자동 승인 명령",
                body: "아래 명령은 AutoRun 실행 시 사용자 확인 없이 자동으로 실행돼요. gh/glab 읽기 명령, git status 등이 기본 포함돼요."
            )

            // 기본 allow list
            patternGroup(
                title: "기본 자동 승인 (수정 불가)",
                patterns: CommandPolicyMatrix.defaultAllowList + CommandPolicyMatrix.defaultAllowPatterns,
                isDefault: true,
                onDelete: nil
            )

            // 사용자 정의 allow patterns
            if !userAllowPatterns.isEmpty {
                patternGroup(
                    title: "내가 추가한 자동 승인",
                    patterns: userAllowPatterns,
                    isDefault: false,
                    onDelete: { pattern in
                        policy = {
                            var p = policy
                            p.allowPatterns = p.allowPatterns.filter { $0 != pattern }
                            p.allowList = p.allowList.filter { $0 != pattern }
                            return p
                        }()
                    }
                )
            }

            // 추가 입력
            addPatternField(
                placeholder: "명령 prefix 또는 정규식 (예: ^gh\\s+pr\\s+create)",
                value: $newAllowPattern,
                error: allowPatternError,
                color: Theme.Color.success
            ) {
                addAllowPattern()
            }
        }
    }

    // MARK: - 차단 섹션

    private var denySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            infoCard(
                icon: "xmark.circle.fill",
                color: Theme.Color.danger,
                title: "차단 명령",
                body: "아래 패턴에 일치하는 명령은 AutoRun에서 즉시 차단돼요. git push --force, rm -rf 등 위험 명령이 기본 포함돼요."
            )

            // 기본 deny patterns
            patternGroup(
                title: "기본 차단 (수정 불가)",
                patterns: CommandPolicyMatrix.defaultDenyPatterns,
                isDefault: true,
                onDelete: nil
            )

            // 사용자 정의 deny patterns
            if !userDenyPatterns.isEmpty {
                patternGroup(
                    title: "내가 추가한 차단",
                    patterns: userDenyPatterns,
                    isDefault: false,
                    onDelete: { pattern in
                        policy = {
                            var p = policy
                            p.denyPatterns = p.denyPatterns.filter { $0 != pattern }
                            return p
                        }()
                    }
                )
            }

            // 추가 입력
            addPatternField(
                placeholder: "차단할 명령 정규식 (예: ^gh\\s+repo\\s+delete)",
                value: $newDenyPattern,
                error: denyPatternError,
                color: Theme.Color.danger
            ) {
                addDenyPattern()
            }
        }
    }

    // MARK: - 미리보기 섹션

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            infoCard(
                icon: "eye.fill",
                color: Theme.Color.accent,
                title: "정책 미리보기",
                body: "명령어를 입력하면 현재 정책이 어떻게 적용되는지 미리 확인할 수 있어요."
            )
            PolicyPreviewRow(policy: policy)
        }
    }

    // MARK: - 컴포넌트

    private func infoCard(icon: String, color: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 20, alignment: .center)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.Typography.small.weight(.semibold))
                    .foregroundStyle(Theme.Color.text)
                Text(body)
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Spacing.md)
        .background(color.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private func patternGroup(
        title: String,
        patterns: [String],
        isDefault: Bool,
        onDelete: ((String) -> Void)?
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.small.weight(.semibold))
                .foregroundStyle(Theme.Color.textSecondary)
            VStack(spacing: 2) {
                ForEach(patterns, id: \.self) { pattern in
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(pattern)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(isDefault ? Theme.Color.textSecondary : Theme.Color.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                        if let onDelete, !isDefault {
                            Button {
                                onDelete(pattern)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.Color.danger.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 5)
                    .background(isDefault ? Theme.Color.surfaceHi.opacity(0.5) : Theme.Color.surfaceHi)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }
            }
        }
    }

    private func addPatternField(
        placeholder: String,
        value: Binding<String>,
        error: String?,
        color: Color,
        onAdd: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("패턴 추가")
                .font(Theme.Typography.small.weight(.semibold))
                .foregroundStyle(Theme.Color.textSecondary)
            HStack(spacing: Theme.Spacing.sm) {
                TextField(placeholder, text: value)
                    .font(.system(.caption, design: .monospaced))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 7)
                    .background(Theme.Color.surfaceHi)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.sm)
                            .stroke(Theme.Color.borderSubtle, lineWidth: 1)
                    )
                Button {
                    onAdd()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(value.wrappedValue.isEmpty ? Theme.Color.textTertiary : color)
                }
                .buttonStyle(.plain)
                .disabled(value.wrappedValue.isEmpty)
            }
            if let error {
                Text(error)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.danger)
            }
        }
    }

    // MARK: - 헬퍼

    private var userAllowPatterns: [String] {
        let defaults = Set(CommandPolicyMatrix.defaultAllowList + CommandPolicyMatrix.defaultAllowPatterns)
        return (policy.allowList + policy.allowPatterns).filter { !defaults.contains($0) }
    }

    private var userDenyPatterns: [String] {
        let defaults = Set(CommandPolicyMatrix.defaultDenyPatterns)
        return policy.denyPatterns.filter { !defaults.contains($0) }
    }

    private func addAllowPattern() {
        let pattern = newAllowPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return }
        if let errorMsg = validateRegex(pattern) {
            allowPatternError = errorMsg
            return
        }
        allowPatternError = nil
        policy = {
            var p = policy
            if !p.allowPatterns.contains(pattern) {
                p.allowPatterns.append(pattern)
            }
            return p
        }()
        newAllowPattern = ""
    }

    private func addDenyPattern() {
        let pattern = newDenyPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return }
        if let errorMsg = validateRegex(pattern) {
            denyPatternError = errorMsg
            return
        }
        denyPatternError = nil
        policy = {
            var p = policy
            if !p.denyPatterns.contains(pattern) {
                p.denyPatterns.append(pattern)
            }
            return p
        }()
        newDenyPattern = ""
    }

    private func validateRegex(_ pattern: String) -> String? {
        do {
            _ = try NSRegularExpression(pattern: pattern)
            return nil
        } catch {
            return "정규식 오류: \(error.localizedDescription)"
        }
    }
}

// MARK: - PolicyPreviewRow

/// 명령어 입력 → 정책 결과 즉시 표시.
private struct PolicyPreviewRow: View {
    let policy: CommandPolicyMatrix
    @State private var commandInput: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            TextField("명령어 입력 (예: gh pr create, git push --force)", text: $commandInput)
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.plain)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 9)
                .background(Theme.Color.surfaceHi)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .stroke(Theme.Color.borderSubtle, lineWidth: 1)
                )

            if !commandInput.isEmpty {
                let result = policy.policy(for: commandInput)
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: result.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(policyColor(result))
                    Text("결과: \(result.displayName)")
                        .font(Theme.Typography.body.weight(.semibold))
                        .foregroundStyle(policyColor(result))
                }
                .padding(Theme.Spacing.md)
                .background(policyColor(result).opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
        }
    }

    private func policyColor(_ policy: CommandPolicy) -> Color {
        switch policy {
        case .allow: return Theme.Color.success
        case .requireConfirmation: return .orange
        case .deny: return Theme.Color.danger
        }
    }
}
