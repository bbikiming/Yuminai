import SwiftUI
import AppKit
import YuminaiCore
import YuminaiUI

/// 워크스페이스 ProjectProfile 편집 sheet (ADR-049).
///
/// **호출 경로**: 사이드바 워크스페이스 우클릭 → "프로젝트 프로필 편집" 메뉴.
/// CreateWorkspaceSheet과 거의 같은 form이지만:
/// - 기존 profile pre-fill
/// - "디스크 다시 감지" 버튼 (auto-detect re-run)
/// - 변경 시 즉시 SwiftData persist
struct EditProjectProfileSheet: View {
    let workspace: Workspace
    let onSave: (ProjectProfile) -> Void
    let onCancel: () -> Void

    @State private var platform: ProjectPlatform
    @State private var primaryLanguage: ProjectLanguage
    @State private var hasBackend: Bool
    @State private var backendLanguage: ProjectLanguage
    @State private var frameworks: String
    @State private var testFramework: String
    @State private var notes: String
    @State private var detectionHint: String?

    init(
        workspace: Workspace,
        onSave: @escaping (ProjectProfile) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.workspace = workspace
        self.onSave = onSave
        self.onCancel = onCancel
        let p = workspace.projectProfile
        _platform = State(initialValue: p.platform)
        _primaryLanguage = State(initialValue: p.primaryLanguage)
        _hasBackend = State(initialValue: p.hasBackend)
        _backendLanguage = State(initialValue: p.backendLanguage ?? .unknown)
        _frameworks = State(initialValue: p.frameworks.joined(separator: ", "))
        _testFramework = State(initialValue: p.testFramework ?? "")
        _notes = State(initialValue: p.notes)
    }

    var body: some View {
        // ADR-074 — YuminaiSheet: footer 고정 + 반응형.
        YuminaiSheet(width: Theme.Layout.sheetWidth, height: 640) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                header
                form
            }
            .padding(Theme.Spacing.xxl)
        } footer: {
            footer
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.stack.fill")
                    .foregroundStyle(Theme.Color.accent)
                Text("프로젝트 프로필 편집")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.text)
            }
            Text("‘\(workspace.name)’ — \(workspace.directoryPath)")
                .font(Theme.Typography.monoSmall)
                .foregroundStyle(Theme.Color.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text("Harness가 모델 routing 시 활용. Claude pane은 spawn 시 system prompt에 자동 inject됩니다.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }

    @ViewBuilder
    private var form: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                FlatButton("디스크에서 다시 감지", variant: .secondary, size: .small) {
                    redetect()
                }
                if let hint = detectionHint {
                    Text(hint)
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.accent)
                        .lineLimit(2)
                }
            }
            HStack(spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Platform")
                    Picker("Platform", selection: $platform) {
                        ForEach(ProjectPlatform.allCases, id: \.self) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    .labelsHidden()
                }
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("주요 언어")
                    Picker("Language", selection: $primaryLanguage) {
                        ForEach(ProjectLanguage.allCases, id: \.self) { l in
                            Text(l.displayName).tag(l)
                        }
                    }
                    .labelsHidden()
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $hasBackend) {
                    Text("백엔드 포함")
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                if hasBackend {
                    Picker("백엔드 언어", selection: $backendLanguage) {
                        ForEach(ProjectLanguage.allCases, id: \.self) { l in
                            Text(l.displayName).tag(l)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                fieldLabel("프레임워크 (쉼표로 구분)")
                FlatTextField("예: Next.js, Tailwind", text: $frameworks)
            }
            VStack(alignment: .leading, spacing: 4) {
                fieldLabel("테스트 도구 (선택)")
                FlatTextField("예: Jest, pytest, XCTest", text: $testFramework)
            }
            VStack(alignment: .leading, spacing: 4) {
                fieldLabel("비고 (선택)")
                FlatTextField("프로젝트 특이사항 — system context에 포함됨", text: $notes)
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            FlatButton("취소", variant: .secondary) { onCancel() }
                .keyboardShortcut(.escape, modifiers: [])
            FlatButton("저장", variant: .primary) { save() }
                .keyboardShortcut(.return, modifiers: [.command])
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.micro)
            .foregroundStyle(Theme.Color.textTertiary)
            .textCase(.uppercase)
            .tracking(0.6)
    }

    private func save() {
        let fwks = frameworks
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let profile = ProjectProfile(
            platform: platform,
            primaryLanguage: primaryLanguage,
            secondaryLanguages: [],
            hasBackend: hasBackend,
            backendLanguage: hasBackend ? backendLanguage : nil,
            frameworks: fwks,
            testFramework: testFramework.isEmpty ? nil : testFramework,
            notes: notes.trimmingCharacters(in: .whitespaces)
        )
        onSave(profile)
    }

    private func redetect() {
        let detected = ProjectProfileDetector.detect(at: workspace.directoryPath)
        // Apply detected (over current) — 사용자에게 명시 액션
        if detected.platform != .unknown { platform = detected.platform }
        if detected.primaryLanguage != .unknown { primaryLanguage = detected.primaryLanguage }
        hasBackend = detected.hasBackend
        if let bl = detected.backendLanguage { backendLanguage = bl }
        if !detected.frameworks.isEmpty {
            frameworks = detected.frameworks.joined(separator: ", ")
        }
        if let test = detected.testFramework { testFramework = test }
        let summary = detected.systemContextSummary()
        detectionHint = summary == "(프로필 미설정)"
            ? "marker 파일 없음 — 수동 입력 필요"
            : "🔍 다시 감지: \(summary)"
    }
}
