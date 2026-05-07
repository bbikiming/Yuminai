import SwiftUI
import AppKit
import YuminaiCore

/// 새 워크스페이스 생성 시트 — flat 자체 컴포넌트.
/// ADR-048 — ProjectProfile 입력 추가 (platform/언어/백엔드 등). 폴더 선택 시 자동 감지로 미리채움.
/// ADR-115 P1-4 — 감지된 스택에 맞는 번들 추천 카드 추가.
public struct CreateWorkspaceSheet: View {
    @State private var name: String = ""
    @State private var directoryPath: String = ""
    // ADR-048 — ProjectProfile fields
    @State private var profilePlatform: ProjectPlatform = .unknown
    @State private var profileLanguage: ProjectLanguage = .unknown
    @State private var profileHasBackend: Bool = false
    @State private var profileBackendLanguage: ProjectLanguage = .unknown
    @State private var profileFrameworks: String = ""
    @State private var profileTestFramework: String = ""
    @State private var profileNotes: String = ""
    @State private var detectedHint: String?  // 자동 감지된 결과 표시
    // ADR-115 P1-4 — 추천 번들 + 추가 예약 목록
    @State private var recommendedBundles: [StackBundle] = []
    @State private var bundlesToAdd: Set<UUID> = []

    public let onCreate: (Workspace) -> Void
    public let onCancel: () -> Void
    /// **ADR-115 P1-4** — 워크스페이스 생성 후 번들 추가 요청 (선택 번들 배열). nil이면 번들 추천 UI 비활성.
    public let onBundlesSelected: (([StackBundle]) -> Void)?

    public init(
        onCreate: @escaping (Workspace) -> Void,
        onCancel: @escaping () -> Void,
        onBundlesSelected: (([StackBundle]) -> Void)? = nil
    ) {
        self.onCreate = onCreate
        self.onCancel = onCancel
        self.onBundlesSelected = onBundlesSelected
    }

    public var body: some View {
        // ADR-074 — YuminaiSheet container: footer가 ScrollView 밖에 고정, 절대 잘리지 않음.
        // 큰 화면: 컨텐츠가 sheet에 fit → 스크롤 없음.
        // 작은 화면: 컨텐츠만 스크롤, footer는 항상 표시.
        YuminaiSheet(width: Theme.Layout.sheetWidth, height: 640) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                header
                nameAndPathSection
                projectProfileSection
                // ADR-115 P1-4 — 번들 추천 섹션 (감지된 스택에 매칭)
                if !recommendedBundles.isEmpty, onBundlesSelected != nil {
                    bundleRecommendationSection
                }
            }
            .padding(Theme.Spacing.xxl)
        } footer: {
            footer
        }
        .overlay(alignment: .topTrailing) {
            SheetCloseButton(action: onCancel)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("새 워크스페이스 만들기")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Color.text)
            Text("폴더 선택 후 프로젝트 종류를 알려주면 Harness가 모델 routing + system context를 자동 구성해요.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }

    private var nameAndPathSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                fieldLabel("이름")
                FlatTextField("예: 내 새 프로젝트", text: $name)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                fieldLabel("폴더")
                HStack(spacing: Theme.Spacing.sm) {
                    FlatTextField("예: ~/Documents/projects/내-프로젝트", text: $directoryPath)
                    FlatButton("폴더 고르기", variant: .secondary, size: .small) {
                        selectDirectory()
                    }
                }
                if let hint = detectedHint {
                    Text(hint)
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.accent)
                }
            }
        }
    }

    @ViewBuilder
    private var projectProfileSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Color.accent)
                Text("프로젝트 프로필")
                    .font(Theme.Typography.small.weight(.medium))
                    .foregroundStyle(Theme.Color.text)
                Text("(Harness가 모델 routing 시 활용)")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            HStack(spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("Platform")
                    Picker("Platform", selection: $profilePlatform) {
                        ForEach(ProjectPlatform.allCases, id: \.self) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    .labelsHidden()
                }
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("주요 언어")
                    Picker("Language", selection: $profileLanguage) {
                        ForEach(ProjectLanguage.allCases, id: \.self) { l in
                            Text(l.displayName).tag(l)
                        }
                    }
                    .labelsHidden()
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $profileHasBackend) {
                    Text("백엔드 포함")
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                if profileHasBackend {
                    Picker("백엔드 언어", selection: $profileBackendLanguage) {
                        ForEach(ProjectLanguage.allCases, id: \.self) { l in
                            Text(l.displayName).tag(l)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                fieldLabel("프레임워크 (쉼표로 구분)")
                FlatTextField("예: Next.js, Tailwind, tRPC", text: $profileFrameworks)
            }
            VStack(alignment: .leading, spacing: 4) {
                fieldLabel("테스트 도구 (선택)")
                FlatTextField("예: Jest, pytest, XCTest", text: $profileTestFramework)
            }
            VStack(alignment: .leading, spacing: 4) {
                fieldLabel("비고 (선택, 자유 입력 — Harness가 system context에 포함)")
                FlatTextField("예: 실시간 수정 필요, ADR 우선", text: $profileNotes)
            }
        }
    }

    /// **ADR-115 P1-4** — 감지된 스택에 매칭된 번들 추천 카드 영역.
    @ViewBuilder
    private var bundleRecommendationSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Color.accent)
                Text("추천 스택 번들")
                    .font(Theme.Typography.small.weight(.medium))
                    .foregroundStyle(Theme.Color.text)
                Text("이 프로젝트에 어울리는 번들이에요")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            ForEach(recommendedBundles) { bundle in
                bundleCard(bundle)
            }
        }
    }

    @ViewBuilder
    private func bundleCard(_ bundle: StackBundle) -> some View {
        let isSelected = bundlesToAdd.contains(bundle.id)
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: bundle.category.icon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Color.accent)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(bundle.displayName)
                    .font(Theme.Typography.small.weight(.medium))
                    .foregroundStyle(Theme.Color.text)
                Text(bundle.resourceCountDisplay)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            Spacer()
            FlatButton(
                isSelected ? "추가 예약됨" : "라이브러리에 추가",
                icon: isSelected ? "checkmark" : "plus",
                variant: isSelected ? .secondary : .primary,
                size: .small
            ) {
                if isSelected {
                    bundlesToAdd.remove(bundle.id)
                } else {
                    bundlesToAdd.insert(bundle.id)
                }
            }
        }
        .padding(Theme.Spacing.sm)
        .background(isSelected ? Theme.Color.accent.opacity(0.06) : Theme.Color.surfaceHi)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(isSelected ? Theme.Color.accent.opacity(0.3) : Theme.Color.borderSubtle, lineWidth: 0.5)
        )
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(bundle.displayName) — \(bundle.resourceCountDisplay)")
    }

    private var footer: some View {
        HStack {
            Spacer()
            FlatButton("취소", variant: .secondary) { onCancel() }
                .keyboardShortcut(.escape, modifiers: [])
            FlatButton("만들기", variant: .primary) { create() }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!isValid)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.micro)
            .foregroundStyle(Theme.Color.textTertiary)
            .textCase(.uppercase)
            .tracking(0.6)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !directoryPath.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "어떤 폴더에서 시작할까요?"
        panel.prompt = "이 폴더로"
        if panel.runModal() == .OK, let url = panel.url {
            directoryPath = url.path
            // ADR-048 — 자동 감지 후 폼 미리채움
            applyAutoDetection(at: url.path)
        }
    }

    /// ProjectProfileDetector 결과로 폼 미리채움. 사용자는 자유 수정 가능.
    /// ADR-115 P1-4 — 감지된 스택으로 번들 추천도 함께 계산.
    private func applyAutoDetection(at path: String) {
        let detected = ProjectProfileDetector.detect(at: path)
        // 자동 감지된 값이 .unknown이 아니면 폼에 반영
        if detected.platform != .unknown {
            profilePlatform = detected.platform
        }
        if detected.primaryLanguage != .unknown {
            profileLanguage = detected.primaryLanguage
        }
        if detected.hasBackend {
            profileHasBackend = true
            if let bl = detected.backendLanguage {
                profileBackendLanguage = bl
            }
        }
        if !detected.frameworks.isEmpty {
            profileFrameworks = detected.frameworks.joined(separator: ", ")
        }
        if let test = detected.testFramework {
            profileTestFramework = test
        }
        // 사용자에게 hint 표시
        let summary = detected.systemContextSummary()
        detectedHint = summary == "(프로필 미설정)"
            ? "자동 감지 marker 파일 없음 — 수동 입력하세요"
            : "🔍 자동 감지: \(summary) — 필요하면 수정하세요"

        // ADR-115 P1-4 — 감지된 profile로 번들 매칭 추천 계산
        recommendedBundles = StackBundleCatalog.findMatching(for: detected, limit: 3)
        bundlesToAdd = []  // 새 감지마다 선택 초기화
    }

    private func create() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedPath = directoryPath.trimmingCharacters(in: .whitespaces)
        let expanded = NSString(string: trimmedPath).expandingTildeInPath
        // ADR-048 — profile 구성
        let frameworks = profileFrameworks
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let profile = ProjectProfile(
            platform: profilePlatform,
            primaryLanguage: profileLanguage,
            secondaryLanguages: [],
            hasBackend: profileHasBackend,
            backendLanguage: profileHasBackend ? profileBackendLanguage : nil,
            frameworks: frameworks,
            testFramework: profileTestFramework.isEmpty ? nil : profileTestFramework,
            notes: profileNotes.trimmingCharacters(in: .whitespaces)
        )
        onCreate(Workspace(name: trimmedName, directoryPath: expanded, projectProfile: profile))
        // ADR-115 P1-4 — 선택된 번들을 호출자에 전달
        let selected = recommendedBundles.filter { bundlesToAdd.contains($0.id) }
        if !selected.isEmpty {
            onBundlesSelected?(selected)
        }
    }
}
