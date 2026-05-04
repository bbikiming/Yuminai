import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-094 Phase 3** — 커맨드 추가/편집 sheet.
///
/// `TelegramBotEditSheet` 패턴을 따름.
struct CommandEditSheet: View {
    let existing: TelegramCommand?
    let onSave: (TelegramCommand) -> Void
    let onCancel: () -> Void

    @State private var trigger: String
    @State private var description: String
    @State private var permissionMode: PermissionMode
    @State private var allowedUserIdsText: String
    @State private var requiresHITL: Bool
    @State private var enabled: Bool

    enum PermissionMode: String, CaseIterable, Identifiable {
        case anyUser = "전체 사용자"
        case admin = "관리자"
        case userIds = "특정 IDs"
        var id: String { rawValue }
    }

    init(
        existing: TelegramCommand?,
        onSave: @escaping (TelegramCommand) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.existing = existing
        self.onSave = onSave
        self.onCancel = onCancel

        _trigger = State(initialValue: existing?.trigger ?? "/")
        _description = State(initialValue: existing?.description ?? "")
        _requiresHITL = State(initialValue: existing?.requiresHITL ?? false)
        _enabled = State(initialValue: existing?.enabled ?? true)

        switch existing?.permission {
        case .admin:
            _permissionMode = State(initialValue: .admin)
            _allowedUserIdsText = State(initialValue: "")
        case .userIds(let ids):
            _permissionMode = State(initialValue: .userIds)
            _allowedUserIdsText = State(initialValue: ids.map(String.init).joined(separator: ", "))
        default:
            _permissionMode = State(initialValue: .anyUser)
            _allowedUserIdsText = State(initialValue: "")
        }
    }

    var body: some View {
        YuminaiSheet(width: 480, height: 420) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text(existing == nil ? "새 커맨드 추가" : "커맨드 편집")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Color.text)

                Form {
                    Section {
                        TextField("/trigger", text: $trigger)
                            .autocorrectionDisabled()
                            .help("예: /run, /deploy — 반드시 '/'로 시작, 최대 32자")
                        TextField("설명", text: $description, axis: .vertical)
                            .lineLimit(2...3)
                            .help("텔레그램 봇 명령 메뉴에 표시됩니다 (최대 256자)")
                    } header: {
                        Text("기본")
                    }

                    Section {
                        Picker("접근 허가", selection: $permissionMode) {
                            ForEach(PermissionMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        if permissionMode == .userIds {
                            TextField("사용 가능한 사람 (텔레그램 사용자 번호, 콤마 구분)", text: $allowedUserIdsText)
                                .autocorrectionDisabled()
                                .help("예: 123456789, 987654321")
                        }
                    } header: {
                        Text("접근 허가")
                    }

                    Section {
                        Toggle("위험 명령 확인 필요", isOn: $requiresHITL)
                            .help("켜면 이 명령어 실행 전 데스크탑에서 확인 요청")
                        Toggle("활성화", isOn: $enabled)
                            .help("꺼면 텔레그램 봇 명령 메뉴 등록 및 라우팅에서 제외")
                    } header: {
                        Text("동작")
                    }
                }
                .formStyle(.grouped)
            }
            .padding(Theme.Spacing.lg)
        } footer: {
            HStack {
                if let validation = validationError {
                    Text(validation)
                        .font(Theme.Typography.micro)
                        .foregroundStyle(.red)
                }
                Spacer()
                FlatButton("취소", variant: .secondary, action: onCancel)
                FlatButton("저장", variant: .primary) { save() }
                    .disabled(validationError != nil)
            }
        }
    }

    // MARK: - Validation

    private var validationError: String? {
        if !trigger.hasPrefix("/") { return "커맨드는 '/'로 시작해야 합니다" }
        let cmd = trigger.dropFirst()
        if cmd.isEmpty { return "커맨드 이름을 입력하세요" }
        if cmd.count > 32 { return "커맨드 이름은 32자 이하" }
        if description.isEmpty { return "설명을 입력하세요" }
        if description.count > 256 { return "설명은 256자 이하" }
        return nil
    }

    // MARK: - Save

    private func save() {
        guard validationError == nil else { return }
        let permission: TelegramCommand.Permission
        switch permissionMode {
        case .anyUser: permission = .anyUser
        case .admin: permission = .admin
        case .userIds:
            let ids = allowedUserIdsText
                .split(separator: ",")
                .compactMap { Int64($0.trimmingCharacters(in: .whitespaces)) }
            permission = .userIds(ids)
        }

        let cmd = TelegramCommand(
            id: existing?.id ?? UUID(),
            trigger: trigger,
            description: description,
            permission: permission,
            requiresHITL: requiresHITL,
            enabled: enabled
        )
        onSave(cmd)
    }
}
