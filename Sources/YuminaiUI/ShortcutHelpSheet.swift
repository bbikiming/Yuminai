import SwiftUI

/// 단축키 도움말 — 모든 단축키 카테고리별 정리 (C1).
public struct ShortcutHelpSheet: View {
    public let onClose: () -> Void

    public init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            FlatHDivider()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    scenariosSection
                    ForEach(Self.categories) { cat in
                        categorySection(cat)
                    }
                }
                .padding(Theme.Spacing.lg)
            }
        }
        // ADR-073 — 반응형. 내부 ScrollView 있어 wrap=false.
        .yuminaiSheetFrame(width: 560, height: 640, wrapInScrollView: false)
        .background(Theme.Color.bg)
    }

    private var header: some View {
        HStack {
            Text("도움말")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Color.text)
            Spacer()
            FlatButton("닫기", variant: .secondary, size: .small, action: onClose)
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(Theme.Spacing.lg)
    }

    @ViewBuilder
    private var scenariosSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("주요 시나리오 — GUI에서 어디?")
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Color.textSecondary)
                .textCase(.uppercase)
                .tracking(0.6)

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(Self.scenarios) { scenario in
                    scenarioRow(scenario)
                }
            }
        }
    }

    private func scenarioRow(_ scenario: ScenarioEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: scenario.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Color.accent)
                .frame(width: 22, height: 22)
                .background(Theme.Color.accentMuted)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(scenario.title)
                    .font(Theme.Typography.body.weight(.semibold))
                    .foregroundStyle(Theme.Color.text)
                Text(scenario.howTo)
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Theme.Color.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    static let scenarios: [ScenarioEntry] = [
        .init(
            icon: "plus",
            title: "Codex pane 추가",
            howTo: "Chat 영역 위 탭바의 ‘+’ 버튼 → ‘Codex pane 추가’"
        ),
        .init(
            icon: "rectangle.split.2x1",
            title: "두 pane 동시에 보기",
            howTo: "탭바 오른쪽의 split 아이콘 → ‘좌·우’ 또는 ‘위·아래’ 선택 (panes 2개+ 시 표시)"
        ),
        .init(
            icon: "arrowshape.turn.up.right",
            title: "다른 pane에 위임",
            howTo: "Composer 우측 ‘위임’ 버튼 (↪ 화살표)에서 대상 pane 선택. 또는 입력창에 `@codex` 직접 타이핑"
        ),
        .init(
            icon: "pencil",
            title: "Pane 이름 바꾸기",
            howTo: "탭 더블클릭 또는 우클릭 → ‘이름 바꾸기…’. 의미 있는 이름이 mention 후보로 자동 등장"
        ),
        .init(
            icon: "paperplane",
            title: "텔레그램으로 제어",
            howTo: "사이드바에서 워크스페이스 우클릭 → ‘텔레그램에 연결’. 텔레그램 챗에서 `/help`로 명령어 확인"
        ),
        .init(
            icon: "checkmark.shield",
            title: "테스트 자동 실행 (Delivery)",
            howTo: "사이드바 우클릭 → ‘Delivery 자동화 설정…’. 테스트 명령 입력 + ‘turn 완료 시 자동 실행’ 토글"
        ),
        .init(
            icon: "arrow.triangle.2.circlepath",
            title: "Agent가 만든 변경 검토",
            howTo: "Inspector(⌘⌥I) → ‘변경’ 탭. 파일 row 선택 → diff 보기 → ‘적용’/‘원복’ 버튼"
        ),
        .init(
            icon: "terminal",
            title: "터미널 패널 열기",
            howTo: "Toolbar 우상단 터미널 아이콘(⌘⌥T) → 워크스페이스 dir에서 자동 시작"
        )
    ]

    @ViewBuilder
    private func categorySection(_ cat: ShortcutCategory) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(cat.title)
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.Color.textSecondary)
                .textCase(.uppercase)
                .tracking(0.6)
            VStack(spacing: 1) {
                ForEach(cat.shortcuts) { sc in
                    shortcutRow(sc)
                }
            }
            .background(Theme.Color.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(Theme.Color.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        }
    }

    private func shortcutRow(_ sc: ShortcutEntry) -> some View {
        HStack {
            Text(sc.label)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Color.text)
            Spacer()
            HStack(spacing: 3) {
                ForEach(sc.keys, id: \.self) { key in
                    ShortcutKeyBadge(key)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
    }

    static let categories: [ShortcutCategory] = [
        ShortcutCategory(title: "글로벌", shortcuts: [
            .init(label: "새 워크스페이스", keys: ["⌘", "N"]),
            .init(label: "사이드바 토글", keys: ["⌘", "⌥", "1"]),
            .init(label: "Inspector 토글", keys: ["⌘", "⌥", "I"]),
            .init(label: "사용량 대시보드", keys: ["⌘", "D"]),
            .init(label: "설정", keys: ["⌘", ","]),
            .init(label: "단축키 도움말 (이 화면)", keys: ["⌘", "/"]),
            .init(label: "Command Palette", keys: ["⌘", "K"]),
            .init(label: "워크스페이스 빠른 전환", keys: ["⌘", "1~9"])
        ]),
        // ADR-051 — Harness 카테고리
        ShortcutCategory(title: "Harness (다중 모델)", shortcuts: [
            .init(label: "Command Palette (모든 액션)", keys: ["⌘", "K"]),
            .init(label: "자동 routing 취소 (countdown 중)", keys: ["esc"]),
            .init(label: "Telegram /model claude|codex|auto", keys: ["TG"]),
            .init(label: "Telegram /decompose <설명>", keys: ["TG"]),
            .init(label: "TaskGraph ▶ 실행 (ready task)", keys: ["click"]),
            .init(label: "Walk-through (완료 task)", keys: ["hover→📊"])
        ]),
        ShortcutCategory(title: "채팅", shortcuts: [
            .init(label: "메시지 보내기", keys: ["⌘", "↵"]),
            .init(label: "응답 중단", keys: ["esc"])
        ]),
        // ADR-042 R2.H9 — v0.9+/v1.2+ 추가된 단축키 일괄 노출
        ShortcutCategory(title: "파일 트리/탭 (ADR-038~041)", shortcuts: [
            .init(label: "파일 빠른 검색", keys: ["⌘", "P"]),
            .init(label: "활성 파일 탭 닫기", keys: ["⌘", "⌥", "W"]),
            .init(label: "다음 파일 탭", keys: ["⌘", "⇧", "]"]),
            .init(label: "이전 파일 탭", keys: ["⌘", "⇧", "["]),
            .init(label: "파일 row 삭제 (휴지통)", keys: ["⌫"]),
            .init(label: "파일 다중 선택 토글", keys: ["⌘", "click"]),
            .init(label: "파일 폴더로 이동", keys: ["drag", "drop"])
        ]),
        ShortcutCategory(title: "터미널 (ADR-040~041)", shortcuts: [
            .init(label: "새 터미널 세션", keys: ["⌃", "⇧", "T"]),
            .init(label: "활성 세션 닫기", keys: ["⌃", "⇧", "W"]),
            .init(label: "다음 세션", keys: ["⌃", "Tab"]),
            .init(label: "이전 세션", keys: ["⌃", "⇧", "Tab"])
        ]),
        ShortcutCategory(title: "노트 편집", shortcuts: [
            .init(label: "저장", keys: ["⌘", "S"])
        ])
    ]
}

public struct ShortcutCategory: Identifiable {
    public let id = UUID()
    public let title: String
    public let shortcuts: [ShortcutEntry]
}

public struct ShortcutEntry: Identifiable {
    public let id = UUID()
    public let label: String
    public let keys: [String]
}

public struct ScenarioEntry: Identifiable {
    public let id = UUID()
    public let icon: String
    public let title: String
    public let howTo: String
}
