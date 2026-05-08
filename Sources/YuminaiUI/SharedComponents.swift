import SwiftUI

/// **ADR-139** — 공유 UI 컴포넌트 (LibraryAddButton + StatusBadge + CardIconBox).
///
/// ## 배경
/// 같은 UI 패턴이 5+ 위치에서 각각 다르게 구현되어 있어
/// 스타일 불일치 + 유지보수 중복이 발생했다. 이 파일로 통합한다.
///
/// ## 컴포넌트
/// - `LibraryAddButton`: ProgressView + Image + 텍스트 + Capsule 캡슐 버튼
/// - `StatusBadge`: Capsule + icon + label + tone (5가지 시맨틱 톤)
/// - `CardIconBox`: RoundedRectangle 44×44 + SF Symbol + tint

// MARK: - LibraryAddButton

/// 라이브러리/카탈로그 항목 추가 버튼.
///
/// ## 상태
/// - `.idle`: 기본 추가 버튼 (+ 아이콘)
/// - `.adding`: ProgressView (스피너)
/// - `.added`: 체크마크 (초록)
///
/// ## 사용
/// ```swift
/// LibraryAddButton(state: isAdded ? .added : .idle) {
///     Task { await model.addItem(item) }
/// }
/// ```
public struct LibraryAddButton: View {

    // MARK: - State

    public enum State: Sendable, Equatable {
        case idle
        case adding
        case added
    }

    // MARK: - Props

    public let state: State
    public let action: () -> Void
    public let label: String

    public init(
        state: State = .idle,
        label: String = "추가",
        action: @escaping () -> Void
    ) {
        self.state = state
        self.label = label
        self.action = action
    }

    // MARK: - Body

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                switch state {
                case .idle:
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Color.accent)
                    Text(label)
                        .font(Theme.Typography.small.weight(.medium))
                        .foregroundStyle(Theme.Color.accent)

                case .adding:
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.85)

                case .added:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Color.success)
                    Text("추가됨")
                        .font(Theme.Typography.small.weight(.medium))
                        .foregroundStyle(Theme.Color.success)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(badgeBg)
            )
            .overlay(
                Capsule().stroke(badgeBorder, lineWidth: 0.5)
            )
            .animation(.easeInOut(duration: 0.15), value: state)
        }
        .buttonStyle(.plain)
        .disabled(state == .adding || state == .added)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Private

    private var badgeBg: Color {
        switch state {
        case .idle: return Theme.Color.accent.opacity(0.08)
        case .adding: return Theme.Color.surfaceHi
        case .added: return Theme.Color.success.opacity(0.08)
        }
    }

    private var badgeBorder: Color {
        switch state {
        case .idle: return Theme.Color.accent.opacity(0.25)
        case .adding: return Theme.Color.border
        case .added: return Theme.Color.success.opacity(0.25)
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .idle: return label
        case .adding: return "추가 중..."
        case .added: return "추가됨"
        }
    }
}

// MARK: - StatusBadge

/// 상태/분류 배지 컴포넌트.
///
/// ## 톤 (시맨틱)
/// - `.success`: 초록 (완료, 설치됨, 정상)
/// - `.warning`: 노랑 (주의, 느림, 임박)
/// - `.danger`: 빨강 (에러, 차단, 실패)
/// - `.neutral`: 회색 (중립, 대기, 알 수 없음)
/// - `.info`: 파랑 (정보, 진행 중, 안내)
///
/// ## 사용
/// ```swift
/// StatusBadge(.success, label: "설치됨", systemImage: "checkmark.circle.fill")
/// StatusBadge(.danger, label: "오류", systemImage: "exclamationmark.circle.fill")
/// ```
public struct StatusBadge: View {

    // MARK: - Tone

    public enum Tone: Sendable {
        case success
        case warning
        case danger
        case neutral
        case info

        public var color: Color {
            switch self {
            case .success: return Theme.Color.success
            case .warning: return Theme.Color.warningStrong
            case .danger: return Theme.Color.danger
            case .neutral: return Theme.Color.textTertiary
            case .info: return Theme.Color.infoBlue
            }
        }

        public var bgOpacity: Double { 0.10 }
    }

    // MARK: - Props

    public let tone: Tone
    public let label: String
    public let systemImage: String?

    public init(
        _ tone: Tone,
        label: String,
        systemImage: String? = nil
    ) {
        self.tone = tone
        self.label = label
        self.systemImage = systemImage
    }

    // MARK: - Body

    public var body: some View {
        HStack(spacing: 4) {
            if let icon = systemImage {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tone.color)
                    .accessibilityHidden(true)
            }
            Text(label)
                .font(Theme.Typography.micro)
                .foregroundStyle(tone.color)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tone.color.opacity(tone.bgOpacity))
        .clipShape(Capsule())
        .accessibilityLabel(label)
    }
}

// MARK: - CardIconBox

/// 카드 내 아이콘 박스 (RoundedRectangle 44×44 기본).
///
/// 라이브러리 카드, 검색 결과 카드, 카탈로그 카드 등에서
/// 반복되는 둥근 사각형 아이콘 박스를 추상화한다.
///
/// ## 사용
/// ```swift
/// CardIconBox(systemName: "doc.fill", tint: Theme.Color.accent)
/// CardIconBox(systemName: "folder.fill", tint: .blue, size: 36)
/// ```
public struct CardIconBox: View {

    // MARK: - Props

    public let systemName: String
    public let tint: Color
    public let size: CGFloat
    public let iconRatio: CGFloat  // icon size / box size

    public init(
        systemName: String,
        tint: Color,
        size: CGFloat = 44,
        iconRatio: CGFloat = 0.5
    ) {
        self.systemName = systemName
        self.tint = tint
        self.size = size
        self.iconRatio = iconRatio
    }

    // MARK: - Body

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(tint.opacity(0.12))
                .frame(width: size, height: size)
            Image(systemName: systemName)
                .font(.system(size: size * iconRatio, weight: .medium))
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)
        }
        .accessibilityHidden(true)
    }
}
