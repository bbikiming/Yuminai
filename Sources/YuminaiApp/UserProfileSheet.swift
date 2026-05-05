import SwiftUI
import AppKit
import YuminaiCore
import YuminaiUI

/// **ADR-106** — 사용자 프로필 편집 sheet.
/// **ADR-107** — 이미지 크롭 sheet 연동 + 목표 상태별 동적 GoalContext 입력 + 선호 설정 아코디언 버그 수정.
///
/// CardSection 5장 구조:
/// 1. 프로필 사진 + 이름
/// 2. 직업 + 목표
/// 3. 목표 상태 (RadioCardButton 3개)
/// 4. 목표 상태별 추가 입력 (GoalContext — 동적)
/// 5. 선호 설정 (disclosure — 선호 에이전트 + 추가 컨텍스트)
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
    @State private var showAdvanced: Bool = false
    @State private var isSaving: Bool = false

    /// ImageCropSheet 표시를 위한 원본 이미지 (nil이면 sheet 닫힘).
    @State private var pendingCropImage: NSImage? = nil

    var isFormValid: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        YuminaiSheet(width: 580, height: 780) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                sheetHeader
                photoAndNameCard
                jobAndGoalCard
                goalStatusCard
                goalContextCard
                advancedCard
            }
            .padding(Theme.Spacing.lg)
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

    // MARK: - 헤더

    private var sheetHeader: some View {
        HeaderHero(
            icon: "person.crop.circle.fill",
            iconTint: Theme.Color.accent,
            title: "내 프로필",
            subtitle: "입력한 정보는 모든 워크스페이스에서 Claude / Codex가 참고해요."
        )
    }

    // MARK: - 카드 1: 사진 + 이름

    private var photoAndNameCard: some View {
        CardSection(style: .subtle) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionHeaderRow(
                    icon: "person.crop.circle.fill",
                    iconColor: Theme.Color.accent,
                    title: "프로필 사진 + 이름",
                    required: true
                )

                HStack(spacing: Theme.Spacing.lg) {
                    profileImageView
                    VStack(alignment: .leading, spacing: 6) {
                        Text("표시 이름")
                            .font(Theme.Typography.small.weight(.medium))
                            .foregroundStyle(Theme.Color.text)
                        TextField("예: 김유민", text: $displayName)
                            .textFieldStyle(.roundedBorder)
                        Text("Yuminai 앱에서 표시되는 이름이에요.")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Color.textTertiary)
                    }
                }
            }
        }
    }

    @MainActor
    private var profileImageView: some View {
        ZStack {
            if let path = profileImagePath, let nsImage = NSImage(contentsOfFile: path) {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Theme.Color.surfaceHi)
                    .frame(width: 72, height: 72)
                    .overlay {
                        let initial = displayName.trimmingCharacters(in: .whitespaces).first.map(String.init) ?? ""
                        if initial.isEmpty {
                            Image(systemName: "person.fill")
                                .font(.system(size: 28, weight: .medium))
                                .foregroundStyle(Theme.Color.textSecondary)
                        } else {
                            Text(initial.uppercased())
                                .font(.system(size: 28, weight: .semibold))
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
                            .frame(width: 22, height: 22)
                            .background(Theme.Color.accent)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .offset(x: 4, y: 4)
                }
            }
            .frame(width: 72, height: 72)
        }
        .frame(width: 80, height: 80)
    }

    // MARK: - 카드 2: 직업 + 목표

    private var jobAndGoalCard: some View {
        CardSection(style: .subtle) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionHeaderRow(
                    icon: "briefcase.fill",
                    iconColor: .orange,
                    title: "직업 + 목표"
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text("직업")
                        .font(Theme.Typography.small.weight(.medium))
                        .foregroundStyle(Theme.Color.text)
                    TextField("예: iOS 개발자, 디자이너, 학생, 마케터", text: $jobTitle)
                        .textFieldStyle(.roundedBorder)
                    Text("입력하지 않아도 괜찮아요. AI가 더 맞춤형으로 답변할 수 있어요.")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("주로 하고 싶은 것")
                        .font(Theme.Typography.small.weight(.medium))
                        .foregroundStyle(Theme.Color.text)
                    TextField(
                        "예: iOS 앱 만들기, 백엔드 API 설계, 콘텐츠 기획",
                        text: $primaryGoal,
                        axis: .vertical
                    )
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
                    Text("지금 당장 무엇을 만들고 싶은지 적어 주세요. AI가 맞게 제안해 드릴게요.")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
            }
        }
    }

    // MARK: - 카드 3: 목표 상태

    private var goalStatusCard: some View {
        CardSection(style: .subtle) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionHeaderRow(
                    icon: "scope",
                    iconColor: Theme.Color.success,
                    title: "지금 목표 상태가 어떤가요?"
                )

                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(UserProfile.GoalStatus.allCases) { status in
                        RadioCardButton(
                            isSelected: goalStatus == status,
                            accentColor: Theme.Color.accent,
                            action: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                    goalStatus = status
                                }
                            }
                        ) {
                            HStack(spacing: 10) {
                                Image(systemName: status.icon)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(goalStatus == status ? Theme.Color.accent : Theme.Color.textSecondary)
                                    .frame(width: 24)
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
                    }
                }
            }
        }
    }

    // MARK: - 카드 4: 목표 상태별 GoalContext 입력 (ADR-107)

    @ViewBuilder
    private var goalContextCard: some View {
        CardSection(style: .accent, accentColor: Theme.Color.accent) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionHeaderRow(
                    icon: "text.bubble.fill",
                    iconColor: Theme.Color.accent,
                    title: "목표 상세 (선택)",
                    caption: "AI가 더 맞춤 답변을 드려요"
                )

                // 공통: 관심 키워드
                goalContextField(
                    label: "관심 키워드",
                    placeholder: "예: SwiftUI, AI, 마케팅",
                    helperText: "콤마로 구분해서 적어 주세요.",
                    text: $goalContext.interestKeywords
                )

                Divider()
                    .padding(.vertical, 2)

                // 상태별 동적 입력 필드
                switch goalStatus {
                case .defined:
                    definedContextFields
                case .exploring:
                    exploringContextFields
                case .undecided:
                    undecidedContextFields
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: goalStatus)
    }

    // defined 전용
    @ViewBuilder
    private var definedContextFields: some View {
        goalContextField(
            label: "언제까지 이루고 싶으세요?",
            placeholder: "예: 2026년 6월, 3개월 안에",
            helperText: "마감일을 역산해서 우선순위를 제안해 드려요.",
            text: $goalContext.targetDeadline
        )
        goalContextField(
            label: "지금 가장 큰 장애물은?",
            placeholder: "예: 시간 부족, 기술 학습 필요",
            helperText: "이 장애물을 해소하는 팁을 먼저 알려드릴게요.",
            text: $goalContext.biggestObstacle
        )
    }

    // exploring 전용
    @ViewBuilder
    private var exploringContextFields: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("탐색 중인 옵션들")
                .font(Theme.Typography.small.weight(.medium))
                .foregroundStyle(Theme.Color.text)
            TextField(
                "한 줄에 하나씩 적어 주세요\n예: SwiftUI 앱\nReact 웹 서비스",
                text: $goalContext.exploringOptions,
                axis: .vertical
            )
            .lineLimit(2...5)
            .textFieldStyle(.roundedBorder)
            Text("각 옵션의 트레이드오프를 비교해 드릴게요.")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
        }
        goalContextField(
            label: "비교 기준",
            placeholder: "예: 학습 곡선, 시장 수요, 재미",
            helperText: "이 기준에 맞게 옵션들을 정리해 드려요.",
            text: $goalContext.explorationCriteria
        )
    }

    // undecided 전용
    @ViewBuilder
    private var undecidedContextFields: some View {
        goalContextField(
            label: "강점/잘하는 것",
            placeholder: "예: 분석, 디자인 감각, 글쓰기",
            helperText: "강점을 살린 방향을 먼저 제안해 드릴게요.",
            text: $goalContext.strengths
        )
        goalContextField(
            label: "관심사",
            placeholder: "예: 영화, 운동, 새로운 기술",
            helperText: "관심사와 연결되는 아이디어를 찾아드릴게요.",
            text: $goalContext.interests
        )
        VStack(alignment: .leading, spacing: 4) {
            Text("이전 경험")
                .font(Theme.Typography.small.weight(.medium))
                .foregroundStyle(Theme.Color.text)
            TextField(
                "간단한 자기소개나 이전 경험을 적어 주세요",
                text: $goalContext.pastExperience,
                axis: .vertical
            )
            .lineLimit(2...5)
            .textFieldStyle(.roundedBorder)
            Text("경험을 바탕으로 작은 첫 시도부터 제안해 드릴게요.")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
        }
    }

    /// 공통 단일 라인 목표 컨텍스트 입력 필드.
    private func goalContextField(
        label: String,
        placeholder: String,
        helperText: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.Typography.small.weight(.medium))
                .foregroundStyle(Theme.Color.text)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
            Text(helperText)
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
        }
    }

    // MARK: - 카드 5: 선호 설정 (disclosure — 아코디언 버그 수정)

    private var advancedCard: some View {
        CardSection(style: .subtle) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                // 버그 수정: .contentShape(Rectangle()) 추가 — 빈 공간도 클릭 영역으로 처리
                // (이전: HStack 빈 공간 클릭 시 이벤트 미전달)
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showAdvanced.toggle()
                    }
                } label: {
                    HStack {
                        // SectionHeaderRow 대신 inline label — trailing Spacer 포함으로 전체 너비 차지
                        HStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(Theme.Color.textSecondary.opacity(0.12))
                                    .frame(width: 22, height: 22)
                                Image(systemName: "gearshape.2.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.Color.textSecondary)
                            }
                            .accessibilityHidden(true)
                            Text("선호 설정")
                                .font(Theme.Typography.label.weight(.semibold))
                                .foregroundStyle(Theme.Color.text)
                            Text("(선택)")
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Color.textTertiary)
                        }
                        Spacer()
                        Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.Color.textTertiary)
                            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showAdvanced)
                    }
                    .contentShape(Rectangle())  // 핵심: 빈 공간도 클릭 영역
                }
                .buttonStyle(.plain)

                if showAdvanced {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        // 선호 에이전트
                        VStack(alignment: .leading, spacing: 4) {
                            Text("선호 에이전트")
                                .font(Theme.Typography.small.weight(.medium))
                                .foregroundStyle(Theme.Color.text)
                            Picker("", selection: $preferredAgent) {
                                Text("자동 (워크스페이스 설정 따름)").tag(Optional<AgentKind>.none)
                                ForEach(AgentKind.allCases, id: \.self) { kind in
                                    Text(kind.displayName).tag(Optional(kind))
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }

                        // 추가 컨텍스트
                        VStack(alignment: .leading, spacing: 4) {
                            Text("추가 컨텍스트 (AI에게 전달)")
                                .font(Theme.Typography.small.weight(.medium))
                                .foregroundStyle(Theme.Color.text)
                            TextField(
                                "AI가 알아두면 좋을 것을 자유롭게 적어 주세요",
                                text: $additionalContext,
                                axis: .vertical
                            )
                            .lineLimit(4...8)
                            .textFieldStyle(.roundedBorder)
                        }

                        // 안내 callout
                        InfoCallout(tone: .info) {
                            Text("여기 입력한 내용은 모든 워크스페이스의 Claude / Codex가 참고할 수 있게 자동으로 `.harness/rules/USER_PROFILE.md`에 저장돼요.")
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Color.textSecondary)
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
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

    /// 이미지를 선택하고 크롭 sheet를 띄운다. (ADR-107)
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
