import SwiftUI
import AppKit
import YuminaiCore
import YuminaiUI

/// **ADR-108-B / ADR-109** — 사용자 프로필 편집 sheet.
///
/// macOS Settings.app 스타일 좌우 분할 레이아웃:
/// - 좌측 sidebar: 5개 섹션 + 입력 완성도 ✓ 표시 + "미입력 N개" hint (폭 200 고정)
/// - 우측 content: 선택된 섹션의 form fields (GroupBox + PolishedInputField)
/// - 섹션 전환: .opacity transition (slide 깜박임 없음)
/// - 크기: 780×580 (커뮤니티 자료 섹션 추가로 가로 확장)
///
/// **ADR-109 변경:**
/// - sidebar 폭 고정 (200pt) — content 흔들림 해결
/// - PolishedInputField로 입력 필드 통일 (iOS 네이티브 퀄리티)
/// - GroupBox 기반 섹션 카드 레이아웃
/// - "커뮤니티 자료" 섹션 추가 (CommunityResourcesPanel)
struct UserProfileSheet: View {
    @Environment(AppModel.self) private var appModel

    @State private var displayName: String = ""
    @State private var jobTitle: String = ""
    @State private var primaryGoal: String = ""
    @State private var goalStatus: UserProfile.GoalStatus = .undecided
    @State private var goalContext: UserProfile.GoalContext = .default
    @State private var preferredAgent: AgentKind? = nil
    @State private var additionalContext: String = ""
    @State private var profileImagePath: String? = nil
    @State private var isSaving: Bool = false

    /// 현재 선택된 섹션
    @State private var selectedSection: ProfileSection = .basic

    /// ImageCropSheet 표시를 위한 원본 이미지 (nil이면 sheet 닫힘).
    @State private var pendingCropImage: NSImage? = nil

    enum ProfileSection: String, CaseIterable, Identifiable {
        case basic       = "기본 정보"
        case job         = "직업과 하고 싶은 것"
        case goalStatus  = "목표 상태"
        case preferences = "선호 설정"
        case community   = "커뮤니티 자료"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .basic:       return "person.crop.circle.fill"
            case .job:         return "briefcase.fill"
            case .goalStatus:  return "scope"
            case .preferences: return "gearshape.2.fill"
            case .community:   return "cube.box.fill"
            }
        }

        var iconColor: Color {
            switch self {
            case .basic:       return Theme.Color.accent
            case .job:         return .orange
            case .goalStatus:  return Theme.Color.success
            case .preferences: return Theme.Color.textSecondary
            case .community:   return .purple
            }
        }
    }

    var isFormValid: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 각 섹션의 완성도 상태를 계산 (helper 분리 → testable).
    var completionState: UserProfileCompletionState {
        UserProfileCompletionHelper.completionState(
            displayName: displayName,
            jobTitle: jobTitle,
            primaryGoal: primaryGoal,
            goalContext: goalContext,
            additionalContext: additionalContext,
            preferredAgent: preferredAgent
        )
    }

    var body: some View {
        YuminaiSheet(width: 780, height: 580) {
            HStack(spacing: 0) {
                sidebarColumn
                    .frame(width: 200, alignment: .leading)  // ADR-109: 고정 폭 — 흔들림 방지
                    .background(Theme.Color.bgSidebar)
                Divider()
                contentColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } footer: {
            footerRow
        }
        .onAppear(perform: loadCurrentProfile)
        .sheet(isPresented: Binding(
            get: { pendingCropImage != nil },
            set: { if !$0 { pendingCropImage = nil } }
        )) {
            if let img = pendingCropImage {
                ImageCropSheet(originalImage: img) { path in
                    profileImagePath = path
                    pendingCropImage = nil
                } onCancel: {
                    pendingCropImage = nil
                }
            }
        }
    }

    // MARK: - 좌측 Sidebar (폭 200 고정)

    private var sidebarColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 프로필 타이틀
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("프로필")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.Color.text)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.md)

            Divider()
                .padding(.bottom, Theme.Spacing.sm)

            // 섹션 목록 — frame 고정으로 흔들림 방지
            VStack(spacing: 2) {
                ForEach(ProfileSection.allCases) { section in
                    sidebarItem(section: section)
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            // 하단: 미입력 hint
            let incomplete = completionState.incompleteCount
            if incomplete > 0 {
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Color.textTertiary)
                    Text("미입력 \(incomplete)개")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
            }
        }
    }

    /// ProfileSection → UserProfileSection 매핑 (완성도 helper 연결용).
    private func coreSection(for section: ProfileSection) -> UserProfileSection? {
        switch section {
        case .basic:       return .basic
        case .job:         return .job
        case .goalStatus:  return .goalStatus
        case .preferences: return .preferences
        case .community:   return nil  // 완성도 미사용 섹션
        }
    }

    private func sidebarItem(section: ProfileSection) -> some View {
        let isSelected = selectedSection == section
        let isDone: Bool = {
            guard let coreSection = coreSection(for: section) else { return false }
            return completionState.isComplete(section: coreSection)
        }()

        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                selectedSection = section
            }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: section.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? section.iconColor : Theme.Color.textSecondary)
                    .frame(width: 18)

                Text(section.rawValue)
                    .font(Theme.Typography.label.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.Color.text : Theme.Color.textSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.Color.success)
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .fill(isSelected ? Theme.Color.surfaceHi : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 우측 Content

    private var contentColumn: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    switch selectedSection {
                    case .basic:       basicContent
                    case .job:         jobContent
                    case .goalStatus:  goalStatusContent
                    case .preferences: preferencesContent
                    case .community:   communityContent
                    }
                }
                .transition(.opacity)
                .animation(.easeOut(duration: 0.15), value: selectedSection)
                .padding(Theme.Spacing.xl)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.Color.bg)
    }

    // MARK: - 섹션 1: 기본 정보

    private var basicContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            sectionTitle("기본 정보", icon: "person.crop.circle.fill", color: Theme.Color.accent, subtitle: "Yuminai에서 표시되는 이름과 사진을 설정해요.")

            // GroupBox — 이름 입력 묶음
            GroupBox {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    HStack(alignment: .top, spacing: Theme.Spacing.xl) {
                        profileImageView

                        PolishedInputField(
                            label: "표시 이름",
                            placeholder: "예: 김유민",
                            helperText: "Yuminai 앱에서 표시되는 이름이에요.",
                            isRequired: true,
                            text: $displayName
                        )
                        .frame(maxWidth: 260)
                    }
                }
            }
        }
    }

    @MainActor
    private var profileImageView: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ZStack {
                if let path = profileImagePath, let nsImage = NSImage(contentsOfFile: path) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Theme.Color.surfaceHi)
                        .frame(width: 80, height: 80)
                        .overlay {
                            let initial = displayName.trimmingCharacters(in: .whitespaces).first.map(String.init) ?? ""
                            if initial.isEmpty {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 32, weight: .medium))
                                    .foregroundStyle(Theme.Color.textSecondary)
                            } else {
                                Text(initial.uppercased())
                                    .font(.system(size: 32, weight: .semibold))
                                    .foregroundStyle(Theme.Color.textSecondary)
                            }
                        }
                }

                // 편집 버튼 오버레이
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            Task { @MainActor in
                                await selectAndCropImage()
                            }
                        } label: {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(Theme.Color.accent)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .offset(x: 4, y: 4)
                    }
                }
                .frame(width: 80, height: 80)
            }
            .frame(width: 88, height: 88)

            Button("사진 변경") {
                Task { @MainActor in await selectAndCropImage() }
            }
            .font(Theme.Typography.micro)
            .foregroundStyle(Theme.Color.accent)
            .buttonStyle(.plain)
        }
    }

    // MARK: - 섹션 2: 직업 + 목표

    private var jobContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            sectionTitle("직업과 하고 싶은 것", icon: "briefcase.fill", color: .orange, subtitle: "AI가 더 맞춤형으로 답변할 수 있게 알려주세요.")

            GroupBox {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    PolishedInputField(
                        label: "직업",
                        placeholder: "예: iOS 개발자, 디자이너, 학생, 마케터",
                        helperText: "입력하지 않아도 괜찮아요. AI가 더 맞춤형으로 답변할 수 있어요.",
                        text: $jobTitle
                    )

                    Divider()

                    PolishedInputField(
                        label: "주로 하고 싶은 것",
                        placeholder: "예: iOS 앱 만들기, 백엔드 API 설계, 콘텐츠 기획",
                        helperText: "지금 당장 무엇을 만들고 싶은지 적어 주세요. AI가 맞게 제안해 드릴게요.",
                        multiline: true,
                        text: $primaryGoal
                    )
                }
            }
        }
    }

    // MARK: - 섹션 3: 목표 상태 + GoalContext

    private var goalStatusContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            sectionTitle("목표 상태", icon: "scope", color: Theme.Color.success, subtitle: "지금 어떤 상태인지 알려주세요. AI가 맞춰 도와드릴게요.")

            // RadioCardButton 3개
            GroupBox {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(UserProfile.GoalStatus.allCases) { status in
                        RadioCardButton(
                            isSelected: goalStatus == status,
                            accentColor: Theme.Color.accent,
                            action: {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    goalStatus = status
                                }
                            }
                        ) {
                            HStack(spacing: 10) {
                                Image(systemName: status.icon)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(goalStatus == status ? Theme.Color.accent : Theme.Color.textSecondary)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(status.displayName)
                                        .font(Theme.Typography.label.weight(.semibold))
                                        .foregroundStyle(Theme.Color.text)
                                    Text(status.subtitle)
                                        .font(Theme.Typography.micro)
                                        .foregroundStyle(Theme.Color.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }

            // 목표 상세 입력 (GoalContext)
            GroupBox {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text("목표 상세")
                        .font(.headline)
                        .foregroundStyle(Theme.Color.textSecondary)

                    PolishedInputField(
                        label: "관심 키워드",
                        placeholder: "예: SwiftUI, AI, 마케팅 (콤마로 구분)",
                        helperText: "콤마로 구분해서 적어 주세요.",
                        text: $goalContext.interestKeywords
                    )

                    Divider()

                    Group {
                        switch goalStatus {
                        case .defined:    definedContextFields
                        case .exploring:  exploringContextFields
                        case .undecided:  undecidedContextFields
                        }
                    }
                    .transition(.opacity)
                    .animation(.easeOut(duration: 0.15), value: goalStatus)
                }
            }
        }
    }

    @ViewBuilder
    private var definedContextFields: some View {
        PolishedInputField(
            label: "언제까지 이루고 싶으세요?",
            placeholder: "예: 2026년 6월, 3개월 안에",
            helperText: "마감일을 역산해서 우선순위를 제안해 드려요.",
            text: $goalContext.targetDeadline
        )
        Divider()
        PolishedInputField(
            label: "지금 가장 큰 장애물은?",
            placeholder: "예: 시간 부족, 기술 학습 필요",
            helperText: "이 장애물을 해소하는 팁을 먼저 알려드릴게요.",
            text: $goalContext.biggestObstacle
        )
    }

    @ViewBuilder
    private var exploringContextFields: some View {
        PolishedInputField(
            label: "탐색 중인 옵션들",
            placeholder: "한 줄에 하나씩 적어 주세요\n예: SwiftUI 앱\nReact 웹 서비스",
            helperText: "각 옵션의 트레이드오프를 비교해 드릴게요.",
            multiline: true,
            text: $goalContext.exploringOptions
        )
        Divider()
        PolishedInputField(
            label: "비교 기준",
            placeholder: "예: 학습 곡선, 시장 수요, 재미",
            helperText: "이 기준에 맞게 옵션들을 정리해 드려요.",
            text: $goalContext.explorationCriteria
        )
    }

    @ViewBuilder
    private var undecidedContextFields: some View {
        PolishedInputField(
            label: "강점/잘하는 것",
            placeholder: "예: 분석, 디자인 감각, 글쓰기",
            helperText: "강점을 살린 방향을 먼저 제안해 드릴게요.",
            text: $goalContext.strengths
        )
        Divider()
        PolishedInputField(
            label: "관심사",
            placeholder: "예: 영화, 운동, 새로운 기술",
            helperText: "관심사와 연결되는 아이디어를 찾아드릴게요.",
            text: $goalContext.interests
        )
        Divider()
        PolishedInputField(
            label: "이전 경험",
            placeholder: "간단한 자기소개나 이전 경험을 적어 주세요",
            helperText: "경험을 바탕으로 작은 첫 시도부터 제안해 드릴게요.",
            multiline: true,
            text: $goalContext.pastExperience
        )
    }

    // MARK: - 섹션 4: 선호 설정

    private var preferencesContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            sectionTitle("선호 설정", icon: "gearshape.2.fill", color: Theme.Color.textSecondary, subtitle: "에이전트 선호도와 AI에게 전달할 추가 정보를 설정해요.")

            GroupBox {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        HStack(spacing: 3) {
                            Text("선호 에이전트")
                                .font(Theme.Typography.small.weight(.medium))
                                .foregroundStyle(Theme.Color.text)
                        }
                        Picker("", selection: $preferredAgent) {
                            Text("자동 (워크스페이스 설정 따름)").tag(Optional<AgentKind>.none)
                            ForEach(AgentKind.allCases, id: \.self) { kind in
                                Text(kind.displayName).tag(Optional(kind))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 380)
                    }

                    Divider()

                    PolishedInputField(
                        label: "추가 컨텍스트 (AI에게 전달)",
                        placeholder: "AI가 알아두면 좋을 것을 자유롭게 적어 주세요",
                        helperText: nil,
                        multiline: true,
                        text: $additionalContext
                    )
                }
            }

            InfoCallout(tone: .info) {
                Text("여기 입력한 내용은 모든 워크스페이스의 Claude / Codex가 참고할 수 있게 자동으로 `.harness/rules/USER_PROFILE.md`에 저장돼요.")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .frame(maxWidth: 400)
        }
    }

    // MARK: - 섹션 5: 커뮤니티 자료 (ADR-109)

    private var communityContent: some View {
        CommunityResourcesPanel()
    }

    // MARK: - 공통 헬퍼 뷰

    private func sectionTitle(_ title: String, icon: String, color: Color, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.Color.text)
            }
            Text(subtitle)
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }

    // MARK: - 푸터

    private var footerRow: some View {
        HStack {
            if !isFormValid {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Color.danger)
                    Text("표시 이름을 입력해 주세요.")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.danger)
                }
            }
            Spacer()
            FlatButton("취소", variant: .secondary) {
                appModel.showUserProfileSheet = false
            }
            .keyboardShortcut(.escape, modifiers: [])

            FlatButton(isSaving ? "저장 중…" : "저장", variant: .primary) {
                Task { await saveProfile() }
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(!isFormValid || isSaving)
        }
    }

    // MARK: - 로직

    private func loadCurrentProfile() {
        let profile = appModel.preferences.userProfile
        displayName = profile.displayName
        jobTitle = profile.jobTitle
        primaryGoal = profile.primaryGoal
        goalStatus = profile.goalStatus
        goalContext = profile.goalContext
        preferredAgent = profile.preferredAgent
        additionalContext = profile.additionalContext
        profileImagePath = profile.profileImagePath
    }

    @MainActor
    private func selectAndCropImage() async {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "프로필 사진을 선택하세요"
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let image = NSImage(contentsOf: url) else { return }
        pendingCropImage = image
    }

    private func saveProfile() async {
        isSaving = true
        let updated = UserProfile(
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            jobTitle: jobTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            primaryGoal: primaryGoal.trimmingCharacters(in: .whitespacesAndNewlines),
            goalStatus: goalStatus,
            goalContext: goalContext,
            preferredAgent: preferredAgent,
            additionalContext: additionalContext.trimmingCharacters(in: .whitespacesAndNewlines),
            profileImagePath: profileImagePath,
            updatedAt: Date()
        )
        await appModel.updateUserProfile(updated)
        isSaving = false
        appModel.showUserProfileSheet = false
    }
}
