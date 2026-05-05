import SwiftUI

/// **ADR-109** — iOS/macOS 네이티브 퀄리티 입력 필드 컴포넌트.
///
/// iOS Settings.app + macOS 시스템 스타일에 맞는 polished 입력 UI.
/// 라벨 + 필수 표시 + 커스텀 배경 + 헬퍼 텍스트를 일관되게 제공한다.
///
/// 사용 예:
/// ```swift
/// PolishedInputField(
///     label: "이름",
///     placeholder: "예: 김유민",
///     helperText: "앱에서 표시되는 이름이에요.",
///     isRequired: true,
///     text: $name
/// )
/// ```
public struct PolishedInputField: View {

    public let label: String
    public let placeholder: String
    public let helperText: String?
    public let isRequired: Bool
    public let multiline: Bool
    @Binding public var text: String

    @FocusState private var isFocused: Bool

    public init(
        label: String,
        placeholder: String,
        helperText: String? = nil,
        isRequired: Bool = false,
        multiline: Bool = false,
        text: Binding<String>
    ) {
        self.label = label
        self.placeholder = placeholder
        self.helperText = helperText
        self.isRequired = isRequired
        self.multiline = multiline
        self._text = text
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            labelRow
            inputField
            if let helperText {
                Text(helperText)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Private

    private var labelRow: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(Theme.Typography.small.weight(.medium))
                .foregroundStyle(Theme.Color.text)
            if isRequired {
                Text("*")
                    .font(Theme.Typography.small.weight(.bold))
                    .foregroundStyle(Theme.Color.danger)
                    .accessibilityLabel("필수 항목")
            }
        }
    }

    private var inputField: some View {
        Group {
            if multiline {
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(3...8)
                    .focused($isFocused)
            } else {
                TextField(placeholder, text: $text)
                    .focused($isFocused)
            }
        }
        .textFieldStyle(.plain)
        .font(Theme.Typography.body)
        .foregroundStyle(Theme.Color.text)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs + 2)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(Theme.Color.surfaceHi)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .stroke(isFocused ? Theme.Color.accent.opacity(0.6) : Theme.Color.borderSubtle, lineWidth: isFocused ? 1.5 : 0.5)
        )
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}
