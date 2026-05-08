import SwiftUI
import AppKit
import YuminaiCore
import YuminaiUI

/// **ADR-133** — GitLab Personal Access Token 입력 sheet.
///
/// GitHubPATSheet 패턴을 차용하며, self-hosted GitLab 호스트 URL 입력을 추가한다.
///
/// PAT 발급 방법:
/// - GitLab.com/settings/access_tokens → 이름 입력, Scopes에서 `api` 또는 `read_api` 선택
/// - 토큰은 Keychain에만 저장. 외부로 전송되지 않음.
struct GitLabPATSheet: View {

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    // MARK: - 상태

    @State private var tokenInput: String = ""
    @State private var hostURLInput: String = ""
    @State private var isSaving: Bool = false
    @State private var isValidating: Bool = false
    @State private var saveError: String? = nil
    @State private var validatedUsername: String? = nil

    // MARK: - 뷰

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    introSection
                    hostURLSection
                    inputSection
                    if let username = validatedUsername {
                        successCallout(username)
                    }
                    if let error = saveError {
                        errorCallout(error)
                    }
                }
                .padding(Theme.Spacing.lg)
            }
        }
        .yuminaiSheetFrame(width: 520, height: 480)
        .background(Theme.Color.bg)
        .onAppear {
            hostURLInput = appModel.preferences.gitlabHostURL
        }
    }

    // MARK: - 헤더

    private var headerRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "key.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Color.gitlab)
            Text("GitLab Personal Access Token")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Color.text)
            Spacer()
            SheetCloseButton(style: .inline) { dismiss() }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.Color.surface)
    }

    // MARK: - 안내 섹션

    private var introSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Color.gitlab)
                    Text("GitLab 검색·자동화에 인증이 필요해요")
                        .font(Theme.Typography.body.weight(.semibold))
                        .foregroundStyle(Theme.Color.text)
                }
                Text("GitLab API는 PAT로 인증해야 프로젝트 검색, 파이프라인 조회 등이 가능해요. 토큰은 이 기기의 Keychain에만 저장되며 외부로 전송되지 않습니다.")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Color.gitlab.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))

            // 토큰 발급 방법 안내
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("토큰 만드는 방법")
                    .font(Theme.Typography.small.weight(.semibold))
                    .foregroundStyle(Theme.Color.textSecondary)
                VStack(alignment: .leading, spacing: 4) {
                    stepRow(number: "1", text: "아래 버튼으로 GitLab 토큰 페이지를 열어요")
                    stepRow(number: "2", text: "이름 입력 (예: \"Yuminai\")")
                    stepRow(number: "3", text: "만료일 설정 (권장: 1년)")
                    stepRow(number: "4", text: "Scopes에서 `api` 또는 `read_api` 선택")
                    stepRow(number: "5", text: "\"Create personal access token\" → 복사 후 아래에 붙여넣기")
                }
                Button {
                    openGitLabTokenPage()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 11, weight: .semibold))
                        Text("GitLab 토큰 페이지 열기")
                            .font(Theme.Typography.small.weight(.medium))
                    }
                    .foregroundStyle(Theme.Color.gitlab)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, 7)
                    .background(Theme.Color.gitlab.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.sm)
                            .stroke(Theme.Color.gitlab.opacity(0.25), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, Theme.Spacing.xs)
            }
        }
    }

    private func stepRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Text(number)
                .font(Theme.Typography.micro.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(Theme.Color.gitlab)
                .clipShape(Circle())
            Text(text)
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 호스트 URL 섹션

    private var hostURLSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("GitLab 호스트 URL")
                    .font(Theme.Typography.small.weight(.semibold))
                    .foregroundStyle(Theme.Color.textSecondary)
                Spacer()
                Text("self-hosted가 아니면 기본값 유지")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            TextField("https://gitlab.com", text: $hostURLInput)
                .font(Theme.Typography.body)
                .textFieldStyle(.plain)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 9)
                .background(Theme.Color.surfaceHi)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .stroke(Theme.Color.borderSubtle, lineWidth: 1)
                )
        }
    }

    // MARK: - 토큰 입력 섹션

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("토큰 입력")
                .font(Theme.Typography.small.weight(.semibold))
                .foregroundStyle(Theme.Color.textSecondary)

            VStack(alignment: .leading, spacing: 6) {
                SecureField("glpat-xxxx… 또는 기타 GitLab PAT", text: $tokenInput)
                    .font(Theme.Typography.body.weight(.medium))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 9)
                    .background(Theme.Color.surfaceHi)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.md)
                            .stroke(
                                validationBorderColor,
                                lineWidth: tokenInput.isEmpty ? 1 : 1.5
                            )
                    )

                // Scope 안내
                HStack(spacing: 4) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Color.textTertiary)
                    Text("권장 scope: `api` (전체 접근) 또는 `read_api` (읽기 전용)")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Color.textTertiary)
                }
            }

            // 검증 + 저장 버튼
            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    Task { await validateAndSavePAT() }
                } label: {
                    HStack(spacing: 4) {
                        if isSaving || isValidating {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(isValidating ? "검증 중…" : isSaving ? "저장 중…" : "검증 후 Keychain에 저장")
                            .font(Theme.Typography.body.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, 8)
                    .background(canSave && !isSaving && !isValidating ? Theme.Color.gitlab : Theme.Color.surfaceHi)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                }
                .buttonStyle(.plain)
                .disabled(!canSave || isSaving || isValidating)

                if appModel.preferences.hasGitLabPAT {
                    Button {
                        Task { await removePAT() }
                    } label: {
                        Text("토큰 삭제")
                            .font(Theme.Typography.small.weight(.medium))
                            .foregroundStyle(Theme.Color.danger)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 성공 callout

    private func successCallout(_ username: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Color.success)
            Text("인증 성공! GitLab 사용자: **\(username)**")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.success)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.success.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    // MARK: - 오류 callout

    private func errorCallout(_ message: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Color.danger)
            Text(message)
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.danger.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    // MARK: - 헬퍼

    private var canSave: Bool {
        !tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var validationBorderColor: Color {
        if tokenInput.isEmpty { return Theme.Color.borderSubtle }
        if validatedUsername != nil { return Theme.Color.success.opacity(0.6) }
        return Theme.Color.borderSubtle
    }

    private func openGitLabTokenPage() {
        let host = hostURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = host.isEmpty ? "https://gitlab.com" : host
        if let url = URL(string: "\(base)/-/user_settings/personal_access_tokens") {
            NSWorkspace.shared.open(url)
        }
    }

    private func validateAndSavePAT() async {
        let token = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let hostRaw = hostURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let hostString = hostRaw.isEmpty ? "https://gitlab.com" : hostRaw
        guard !token.isEmpty, let hostURL = URL(string: hostString) else { return }

        isValidating = true
        saveError = nil
        validatedUsername = nil

        // PAT 유효성 검증
        let client = GitLabSearchClient(hostURL: hostURL, token: token)
        do {
            let username = try await client.validateToken()
            validatedUsername = username
        } catch {
            saveError = "토큰 검증 실패: \(error.localizedDescription)"
            isValidating = false
            return
        }
        isValidating = false

        // Keychain 저장
        isSaving = true
        do {
            try await appModel.saveGitLabPAT(token)
            // 호스트 URL 저장
            appModel.preferences.gitlabHostURL = hostString
            await appModel.savePreferences()
            dismiss()
        } catch {
            saveError = "저장 실패: \(error.localizedDescription)"
        }
        isSaving = false
    }

    private func removePAT() async {
        await appModel.removeGitLabPAT()
        validatedUsername = nil
        tokenInput = ""
    }
}
