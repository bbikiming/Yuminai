import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-078 Phase 4** — 태그 생성/편집 sheet (이름 + 색상).
///
/// Folder와 달리 아이콘 없음 (tag는 항상 "tag.fill" 또는 dot indicator만).
struct TagEditSheet: View {
    let existingTag: WorkspaceTag?
    let onConfirm: (_ name: String, _ colorName: String) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var selectedColor: FolderColorPreset = .blue
    @FocusState private var inputFocused: Bool

    var body: some View {
        YuminaiSheet(width: 460, height: 320) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                preview
                nameField
                colorPicker
            }
            .padding(Theme.Spacing.xl)
        } footer: {
            HStack {
                Spacer()
                FlatButton("취소", variant: .secondary, action: onCancel)
                    .keyboardShortcut(.escape, modifiers: [])
                FlatButton(existingTag == nil ? "만들기" : "저장", variant: .primary) {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    onConfirm(trimmed, selectedColor.rawValue)
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            if let tag = existingTag {
                name = tag.name
                selectedColor = FolderColorPreset(rawValue: tag.colorName) ?? .blue
            }
            inputFocused = true
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(existingTag == nil ? "새 태그 만들기" : "태그 편집")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Color.text)
            Text("태그는 워크스페이스에 다중 적용 가능 (폴더와 별개).")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }

    private var preview: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Theme.Color.folderColor(for: selectedColor.rawValue))
                .frame(width: 8, height: 8)
            Text(name.isEmpty ? "태그 이름" : name)
                .font(Theme.Typography.small.weight(.medium))
                .foregroundStyle(name.isEmpty ? Theme.Color.textTertiary : Theme.Color.text)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Theme.Color.surface)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Theme.Color.borderSubtle, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("미리보기, \(name.isEmpty ? "이름 없음" : name), \(selectedColor.displayName)")
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("이름")
            FlatTextField("예: 긴급, ClientA, iOS", text: $name)
                .focused($inputFocused)
                .accessibilityLabel("태그 이름")
        }
    }

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("색상")
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
                    .frame(width: 24, height: 24)
                if isSelected {
                    Circle()
                        .stroke(Theme.Color.text, lineWidth: 2)
                        .frame(width: 28, height: 28)
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .help(color.displayName)
        .accessibilityLabel(color.displayName)
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
