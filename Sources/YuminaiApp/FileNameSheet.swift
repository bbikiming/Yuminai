import SwiftUI
import YuminaiCore
import YuminaiUI

/// 파일/폴더 이름 입력 sheet — 새 파일 / 새 폴더 / 이름 변경 공통 (ADR-039 R3).
///
/// **단순화**: 텍스트 1개 입력 + 위치 표시 + Enter/Esc.
/// 확장자 자동 추가 같은 polish는 v1.1+.
struct FileNameSheet: View {
    let intent: FileNameSheetIntent
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            form
            Divider()
            footer
        }
        // ADR-073 — 짧은 sheet (220px). 작은 화면에서도 잘 표시됨.
        .yuminaiSheetFrame(width: 440, height: 220, wrapInScrollView: false)
        .background(Theme.Color.bg)
        .overlay(alignment: .topTrailing) {
            SheetCloseButton(action: onCancel)
        }
        .onAppear {
            name = intent.initialName
            inputFocused = true
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: intent.icon)
                .foregroundStyle(Theme.Color.accent)
            Text(intent.title)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Color.text)
            Spacer()
        }
        .padding(Theme.Spacing.lg)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if let parent = intent.parentLabel {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Color.textTertiary)
                    Text(parent)
                        .font(Theme.Typography.monoSmall)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            TextField(intent.placeholder, text: $name)
                .textFieldStyle(.roundedBorder)
                .font(Theme.Typography.mono)
                .focused($inputFocused)
                .onSubmit { submitIfValid() }
            InlineHint(intent.hint, icon: "info.circle", kind: .info)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("취소", action: onCancel)
                .keyboardShortcut(.escape, modifiers: [])
            Button(intent.submitLabel) { submitIfValid() }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
        }
        .padding(Theme.Spacing.md)
    }

    private var isValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.contains("/") && !trimmed.contains("\\")
    }

    private func submitIfValid() {
        guard isValid else { return }
        onSubmit(name.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// 파일 삭제 확인 alert state.
public struct FileDeleteConfirmation: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let path: String
    public let isFolder: Bool

    public init(path: String, isFolder: Bool) {
        self.path = path
        self.isFolder = isFolder
    }

    public var displayName: String { (path as NSString).lastPathComponent }
    public var title: String { isFolder ? "폴더 삭제" : "파일 삭제" }
    public var message: String {
        let kind = isFolder ? "폴더" : "파일"
        let extra = isFolder ? "\n폴더 안 모든 파일이 함께 삭제됩니다." : ""
        return "‘\(displayName)’ \(kind)을 삭제할까요?\(extra)\n\n복구할 수 없어요. 디스크에서 영구 제거됩니다."
    }
}

/// 파일 이름 입력 sheet의 의도 — 새 파일 / 새 폴더 / 이름 변경.
public enum FileNameSheetIntent: Identifiable, Equatable, Sendable {
    case newFile(parent: String)
    case newFolder(parent: String)
    case rename(path: String, isFolder: Bool)

    public var id: String {
        switch self {
        case .newFile(let p): return "newfile:\(p)"
        case .newFolder(let p): return "newfolder:\(p)"
        case .rename(let p, _): return "rename:\(p)"
        }
    }

    public var title: String {
        switch self {
        case .newFile: return "새 파일"
        case .newFolder: return "새 폴더"
        case .rename(_, let isFolder): return isFolder ? "폴더 이름 변경" : "파일 이름 변경"
        }
    }

    public var icon: String {
        switch self {
        case .newFile: return "doc.badge.plus"
        case .newFolder: return "folder.badge.plus"
        case .rename: return "pencil"
        }
    }

    public var submitLabel: String {
        switch self {
        case .newFile, .newFolder: return "생성"
        case .rename: return "변경"
        }
    }

    public var placeholder: String {
        switch self {
        case .newFile: return "예: NewFile.swift"
        case .newFolder: return "예: helpers"
        case .rename(_, let isFolder): return isFolder ? "새 폴더 이름" : "새 파일 이름"
        }
    }

    public var hint: String {
        switch self {
        case .newFile:
            return "확장자 포함해서 입력하세요 (예: .swift / .ts / .md). 부모 디렉토리에 생성됩니다."
        case .newFolder:
            return "폴더 이름엔 ‘/’ 포함 불가. 중첩 폴더는 한 단계씩 만드세요."
        case .rename:
            return "같은 부모 디렉토리 내에서만 이름이 바뀝니다. 폴더 이동은 외부 IDE 사용."
        }
    }

    /// 입력 필드 초기값 (rename은 현재 이름 prefill, 새로 만들기는 빈 string).
    public var initialName: String {
        switch self {
        case .newFile, .newFolder: return ""
        case .rename(let path, _): return (path as NSString).lastPathComponent
        }
    }

    /// "위치" 표시용 라벨 — root는 "/" 표시.
    public var parentLabel: String? {
        switch self {
        case .newFile(let parent), .newFolder(let parent):
            return parent.isEmpty ? "/" : parent
        case .rename(let path, _):
            let parent = (path as NSString).deletingLastPathComponent
            return parent.isEmpty ? "/" : parent
        }
    }
}
