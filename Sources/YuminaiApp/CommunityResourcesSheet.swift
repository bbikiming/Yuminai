import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-117 + ADR-120** — 커뮤니티 자료 독립 Sheet.
///
/// ADR-117: 사이드바 직접 진입점에서 CommunityResourcesPanel을
/// 별도 Sheet로 감싸 onOpenCommunityResources 액션으로 바로 열 수 있도록 한다.
///
/// ADR-120: 이중 헤더 제거 — Sheet wrapper의 SheetHeader만 사용하고,
/// Panel 내부 headerSection의 제목/아이콘 영역을 제거하여 헤더가 한 번만 보이도록 수정.
/// 또한 .frame(width:height:) 고정 → yuminaiSheetFrame(width:height:) 반응형으로 전환.
///
/// 크기: 860×640 — CommunityResourcesPanel의 넉넉한 표시 공간 확보.
struct CommunityResourcesSheet: View {

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                icon: "archivebox.fill",
                title: "커뮤니티 자료",
                onClose: { dismiss() }
            ) {
                // 액션 버튼 그룹 (ADR-120: Panel에서 Sheet header로 이동)
                HStack(spacing: Theme.Spacing.sm) {
                    Button {
                        appModel.showBundleCatalogSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "rectangle.stack.fill")
                                .font(.system(size: 11, weight: .semibold))
                            Text("스택 번들")
                                .font(Theme.Typography.small.weight(.medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.Color.accent)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        appModel.showGitHubSearchSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "magnifyingglass.circle.fill")
                                .font(.system(size: 11, weight: .semibold))
                            Text("GitHub 검색")
                                .font(Theme.Typography.small.weight(.medium))
                        }
                        .foregroundStyle(Theme.Color.accent)
                    }
                    .buttonStyle(.plain)

                    // ADR-133 — GitLab 검색 버튼
                    Button {
                        appModel.showGitLabSearchSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "magnifyingglass.circle")
                                .font(.system(size: 11, weight: .semibold))
                            Text("GitLab 검색")
                                .font(Theme.Typography.small.weight(.medium))
                        }
                        .foregroundStyle(Color.orange)
                    }
                    .buttonStyle(.plain)

                    Button {
                        appModel.showCatalogSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.grid.2x2.fill")
                                .font(.system(size: 11, weight: .semibold))
                            Text("전체 카탈로그")
                                .font(Theme.Typography.small.weight(.medium))
                        }
                        .foregroundStyle(Theme.Color.accent)
                    }
                    .buttonStyle(.plain)

                    Button {
                        appModel.showLibrarySheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "books.vertical.fill")
                                .font(.system(size: 11, weight: .semibold))
                            Text("라이브러리 보기")
                                .font(Theme.Typography.small.weight(.medium))
                        }
                        .foregroundStyle(Theme.Color.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            // 패널 본체 — headerSection은 ADR-120에서 숨김 처리됨 (showHeader: false)
            // ADR-121: ScrollView를 panel 안에서만. yuminaiSheetFrame의 외부 wrap 비활성화로
            // SheetHeader가 sticky하게 유지됨.
            ScrollView {
                CommunityResourcesPanel(showHeader: false)
                    .environment(appModel)
                    .padding(Theme.Spacing.lg)
            }
        }
        // ADR-121 — wrapInScrollView=false로 외부 ScrollView 제거 → 헤더 sticky
        .yuminaiSheetFrame(width: 860, height: 640, wrapInScrollView: false)
        .background(Theme.Color.bg)
    }
}
