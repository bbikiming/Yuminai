import SwiftUI
import AppKit
import YuminaiCore
import YuminaiUI

/// **ADR-119** — GitHub Personal Access Token 입력 sheet.
///
/// 사용자가 GitHub PAT를 입력하면 Keychain에 저장하고
/// GitHubSearchSheet의 코드 검색 기능이 자동으로 활성화된다.
///
/// 토큰 생성 방법:
/// - github.com/settings/tokens → Generate new token (classic) → `public_repo` scope 선택
struct GitHubPATSheet: View {

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    // MARK: - 상태

    @State private var tokenInput: String = ""
    @State private var isSaving: Bool = false
    @State private var saveError: String? = nil

    // MARK: - 뷰

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    introSection
                    inputSection
                    if let error = saveError {
                        errorCallout(error)
                    }
                }
                .padding(Theme.Spacing.lg)
            }
        }
        .frame(minWidth: 520, minHeight: 420)
        .background(Theme.Color.bg)
    }

    // MARK: - 헤더

    private var headerRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "key.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Color.accent)
            Text("GitHub Personal Access Token")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Color.text)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .buttonStyle(.plain)
            .help("닫기")
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.Color.surface)
    }

    // MARK: - 안내 섹션

    private var introSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // 왜 필요한지
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Color.accent)
                    Text("코드 파일 검색에는 인증이 필요해요")
                        .font(Theme.Typography.body.weight(.semibold))
                        .foregroundStyle(Theme.Color.text)
                }
                Text("GitHub Search Code API (`/search/code`)는 인증된 요청만 허용합니다. PAT를 설정하면 CLAUDE.md, .cursorrules 등 파일을 리포지토리에서 직접 검색할 수 있어요. 토큰은 이 기기의 Keychain에만 저장되며 외부로 전송되지 않습니다.")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Color.accentMuted.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))

            // 토큰 발급 방법 안내
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("토큰 만드는 방법")
                    .font(Theme.Typography.small.weight(.semibold))
                    .foregroundStyle(Theme.Color.textSecondary)
                VStack(alignment: .leading, spacing: 4) {
                    stepRow(number: "1", text: "아래 버튼으로 GitHub 토큰 페이지를 열어요")
                    stepRow(number: "2", text: "\"Generate new token (classic)\" 클릭")
                    stepRow(number: "3", text: "Note에 \"Yuminai\" 등 이름을 입력")
                    stepRow(number: "4", text: "Scopes에서 `public_repo` 선택 (비공개 리포 필요 시 `repo`)")
                    stepRow(number: "5", text: "\"Generate token\" 클릭 → 토큰 복사 후 아래에 붙여넣기")
                }
                Button {
                    openGitHubTokenPage()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 11, weight: .semibold))
                        Text("GitHub 토큰 페이지 열기")
                            .font(Theme.Typography.small.weight(.medium))
                    }
                    .foregroundStyle(Theme.Color.accent)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, 7)
                    .background(Theme.Color.accentMuted.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.sm)
                            .stroke(Theme.Color.accent.opacity(0.25), lineWidth: 0.5)
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
                .background(Theme.Color.accent)
                .clipShape(Circle())
            Text(text)
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 입력 섹션

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("토큰 입력")
                .font(Theme.Typography.small.weight(.semibold))
                .foregroundStyle(Theme.Color.textSecondary)

            // SecureField + 형식 검증
            VStack(alignment: .leading, spacing: 6) {
                SecureField("ghp_xxxx… 또는 github_pat_xxxx…", text: $tokenInput)
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

                if !tokenInput.isEmpty && !isValidPATFormat {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                        Text("토큰은 `ghp_` 또는 `github_pat_`로 시작해야 해요.")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(.orange)
                    }
                }
            }

            // 저장 버튼
            HStack {
                Spacer()
                Button {
                    Task { await savePAT() }
                } label: {
                    HStack(spacing: 4) {
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(isSaving ? "저장 중…" : "Keychain에 저장")
                            .font(Theme.Typography.body.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, 8)
                    .background(canSave && !isSaving ? Theme.Color.accent : Theme.Color.surfaceHi)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                }
                .buttonStyle(.plain)
                .disabled(!canSave || isSaving)
            }
        }
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

    private var isValidPATFormat: Bool {
        let t = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.hasPrefix("ghp_") || t.hasPrefix("github_pat_")
    }

    private var canSave: Bool {
        !tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isValidPATFormat
    }

    private var validationBorderColor: Color {
        if tokenInput.isEmpty { return Theme.Color.borderSubtle }
        return isValidPATFormat ? Theme.Color.success.opacity(0.6) : Color.orange.opacity(0.6)
    }

    private func openGitHubTokenPage() {
        if let url = URL(string: "https://github.com/settings/tokens") {
            NSWorkspace.shared.open(url)
        }
    }

    private func savePAT() async {
        let token = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        isSaving = true
        saveError = nil
        do {
            try await appModel.saveGitHubPAT(token)
            dismiss()
        } catch {
            saveError = "저장 실패: \(error.localizedDescription)"
        }
        isSaving = false
    }
}
