import SwiftUI
import YuminaiCore
import YuminaiUI

/// 워크스페이스의 build/test/lint 명령 + 자동 실행 정책 편집 (ADR-029).
struct WorkspaceDeliverySheet: View {
    let workspaceName: String
    @State var draft: DeliveryConfig
    let onApply: (DeliveryConfig) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                Form {
                    commandsSection
                    policySection
                    helpSection
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
            }
            Divider()
            footer
        }
        .frame(width: 580, height: 540)
        .background(Theme.Color.bg)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Delivery 자동화")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Color.text)
            Text(workspaceName)
                .font(Theme.Typography.monoSmall)
                .foregroundStyle(Theme.Color.textTertiary)
            Spacer()
        }
        .padding(Theme.Spacing.lg)
    }

    @ViewBuilder
    private var commandsSection: some View {
        Section {
            commandField(
                label: "테스트",
                hint: "agent turn이 끝나면 자동 실행할 테스트 명령. 실패 시 결과가 다음 turn에 자동 첨부됩니다.",
                placeholder: "예: swift test, npm test, pytest -q",
                text: Binding(
                    get: { draft.testCommand ?? "" },
                    set: { draft.testCommand = $0.isEmpty ? nil : $0 }
                )
            )
            commandField(
                label: "린트",
                hint: "테스트 성공 후 추가로 실행할 린트 명령. 실패해도 다음 turn에 첨부되지만 lint 실패는 보통 빌드를 막지는 않아요.",
                placeholder: "예: swiftlint, eslint ., ruff check",
                text: Binding(
                    get: { draft.lintCommand ?? "" },
                    set: { draft.lintCommand = $0.isEmpty ? nil : $0 }
                )
            )
            commandField(
                label: "빌드",
                hint: "수동 실행용 빌드 명령. 자동 trigger는 테스트가 우선이고, 빌드는 Inspector ‘변경’ 탭에서 명시 실행합니다.",
                placeholder: "예: swift build, npm run build",
                text: Binding(
                    get: { draft.buildCommand ?? "" },
                    set: { draft.buildCommand = $0.isEmpty ? nil : $0 }
                )
            )
        } header: {
            HStack(spacing: 4) {
                Text("명령")
                HelpHint(
                    "워크스페이스 디렉토리에서 zsh로 실행됩니다. 환경변수는 사용자 zsh 설정(.zshrc 등) 그대로 상속받아요.",
                    title: "실행 환경",
                    placement: .trailing
                )
            }
        } footer: {
            Text("실행 환경: `/bin/zsh -lc \"<명령>\"` — 사용자 shell config(login shell) 적용")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var policySection: some View {
        Section {
            Toggle(isOn: $draft.autoRunOnTurnComplete) {
                LabelWithHint(
                    "agent turn 완료 시 자동 실행",
                    hint: "켜져있으면 Claude/Codex가 응답을 마칠 때마다 테스트 → 린트 순서로 자동 실행됩니다. 꺼져있으면 사용자가 수동(Inspector ‘변경’ 탭)으로 실행해야 해요."
                )
            }
            Toggle(isOn: $draft.autoFeedFailureToAgent) {
                LabelWithHint(
                    "실패 결과를 다음 turn에 자동 첨부",
                    hint: "테스트가 실패하면 stderr 마지막 50줄이 다음 사용자 메시지 앞에 자동으로 prepend됩니다. agent가 fix 시도를 자연스럽게 이어갈 수 있어요. 무한 루프 방지를 위해 max-attempts hard cap이 적용됩니다."
                )
            }
            .disabled(!draft.autoRunOnTurnComplete)

            HStack {
                LabelWithHint(
                    "최대 자동 시도",
                    hint: "이 횟수를 넘기면 자동 실행이 멈추고 사용자 에스컬레이션 메시지가 표시됩니다. Devin 패턴의 step budget입니다."
                )
                Spacer()
                Stepper(value: $draft.maxAttempts, in: 1...10) {
                    Text("\(draft.maxAttempts)회").font(Theme.Typography.monoSmall)
                }
                .frame(width: 140)
            }
            HStack {
                LabelWithHint(
                    "타임아웃",
                    hint: "한 명령의 최대 실행 시간. 초과하면 SIGTERM → 0.5초 후 SIGKILL. 빌드가 오래 걸리는 프로젝트는 늘려주세요."
                )
                Spacer()
                Stepper(value: $draft.timeoutSeconds, in: 30...1800, step: 30) {
                    Text("\(draft.timeoutSeconds)초").font(Theme.Typography.monoSmall)
                }
                .frame(width: 160)
            }
        } header: {
            Text("정책")
        } footer: {
            Text("권고: agent fix loop은 단순할수록 좋아요. mini-SWE-agent는 100줄로 SWE-bench 65%를 달성했습니다 (Princeton, NeurIPS 2024).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var helpSection: some View {
        Section {
            InlineHint(
                "git 저장소 + 명령 1개 이상이 설정돼야 동작해요. 자동 실행이 꺼져있어도 Inspector ‘변경’ 탭에서 수동 실행은 가능합니다.",
                icon: "lightbulb",
                kind: .tip
            )
            InlineHint(
                "테스트 출력은 워크스페이스 터미널(⌘⌥T)에 표시되지 않아요. 별도 ‘Delivery’ 영역(Inspector ‘변경’ 탭 하단)에서 확인합니다.",
                icon: "info.circle",
                kind: .info
            )
        } header: {
            Text("도움말")
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("취소", action: onCancel)
                .keyboardShortcut(.escape, modifiers: [])
            Button("저장") { onApply(draft) }
                .keyboardShortcut(.return, modifiers: [.command])
                .buttonStyle(.borderedProminent)
        }
        .padding(Theme.Spacing.md)
    }

    private func commandField(
        label: String,
        hint: String,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        LabeledContent {
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(Theme.Typography.monoSmall)
        } label: {
            LabelWithHint(label, hint: hint)
        }
    }
}
