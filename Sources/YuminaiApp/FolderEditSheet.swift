import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-077 Phase 2** — 폴더 customization sheet (이름 + 색상 + 아이콘).
///
/// FolderRenameSheet의 발전형:
/// - 이름 입력 (기존 + 신규)
/// - **색상 picker** (10개 preset)
/// - **아이콘 picker** (12개 SF Symbol preset)
/// - 미리보기 (위에 폴더 카드)
///
/// 모드:
/// - **생성 모드** (existingFolder == nil): 빈 입력 + default 색상/아이콘
/// - **편집 모드** (existingFolder != nil): 기존 값 prefilled
struct FolderEditSheet: View {
    let existingFolder: WorkspaceFolder?
    let onConfirm: (_ name: String, _ iconName: String, _ colorName: String) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var selectedColor: FolderColorPreset = .accent
    @State private var selectedIcon: FolderIconPreset = .folderFill
    @FocusState private var inputFocused: Bool

    var body: some View {
        // ADR-074 — YuminaiSheet (footer 항상 고정)
        YuminaiSheet(width: 540, height: 540) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                preview
                nameField
                colorPicker
                iconPicker
            }
            .padding(Theme.Spacing.xl)
        } footer: {
            HStack {
                Spacer()
                FlatButton("취소", variant: .secondary, action: onCancel)
                    .keyboardShortcut(.escape, modifiers: [])
                FlatButton(existingFolder == nil ? "만들기" : "저장", variant: .primary) {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    onConfirm(trimmed, selectedIcon.rawValue, selectedColor.rawValue)
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            if let folder = existingFolder {
                name = folder.name
                selectedColor = FolderColorPreset(rawValue: folder.colorName) ?? .accent
                selectedIcon = FolderIconPreset(rawValue: folder.iconName) ?? .folderFill
            }
            inputFocused = true
        }
        .overlay(alignment: .topTrailing) {
            SheetCloseButton(action: onCancel)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(existingFolder == nil ? "새 폴더 만들기" : "폴더 편집")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Color.text)
            Text(existingFolder == nil
                 ? "이름, 색상, 아이콘을 선택하세요."
                 : "폴더 이름, 색상, 아이콘을 변경하세요.")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }

    /// **ADR-077 Phase 2** — 사용자 선택 즉시 반영되는 미리보기.
    private var preview: some View {
        HStack(spacing: 8) {
            Image(systemName: selectedIcon.rawValue)
                .font(.system(size: 18))
                .foregroundStyle(Theme.Color.folderColor(for: selectedColor.rawValue))
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            Text(name.isEmpty ? "폴더 이름" : name)
                .font(Theme.Typography.bodyEmphasis)
                .foregroundStyle(name.isEmpty ? Theme.Color.textTertiary : Theme.Color.text)
            Spacer()
            Text("미리보기")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Color.textTertiary)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("미리보기, \(name.isEmpty ? "이름 없음" : name), \(selectedIcon.displayName), \(selectedColor.displayName)")
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("이름")
            FlatTextField("예: 클라이언트 프로젝트", text: $name)
                .focused($inputFocused)
                .accessibilityLabel("폴더 이름")
        }
    }

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("색상")
            // 10개 preset, 한 줄 grid
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(FolderColorPreset.allCases) { color in
                    colorSwatch(color)
                }
            }
        }
    }

    private func colorSwatch(_ color: FolderColorPreset) -> some View {
        let isSelected = selectedColor == color
        return Button {
            selectedColor = color
        } label: {
            ZStack {
                Circle()
                    .fill(Theme.Color.folderColor(for: color.rawValue))
                    .frame(width: 28, height: 28)
                if isSelected {
                    Circle()
                        .stroke(Theme.Color.text, lineWidth: 2)
                        .frame(width: 32, height: 32)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .help(color.displayName)
        .accessibilityLabel(color.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var iconPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("아이콘")
            // 12개 preset, 6×2 grid
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(48), spacing: 8), count: 6), spacing: 8) {
                ForEach(FolderIconPreset.allCases) { icon in
                    iconCell(icon)
                }
            }
        }
    }

    private func iconCell(_ icon: FolderIconPreset) -> some View {
        let isSelected = selectedIcon == icon
        return Button {
            selectedIcon = icon
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .fill(isSelected ? Theme.Color.folderColor(for: selectedColor.rawValue).opacity(0.20) : Theme.Color.surface)
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(
                        isSelected
                            ? Theme.Color.folderColor(for: selectedColor.rawValue)
                            : Theme.Color.borderSubtle,
                        lineWidth: isSelected ? 2 : 1
                    )
                Image(systemName: icon.rawValue)
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Theme.Color.folderColor(for: selectedColor.rawValue) : Theme.Color.textSecondary)
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .help(icon.displayName)
        .accessibilityLabel(icon.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.micro)
            .foregroundStyle(Theme.Color.textTertiary)
            .textCase(.uppercase)
            .tracking(0.6)
    }
}
