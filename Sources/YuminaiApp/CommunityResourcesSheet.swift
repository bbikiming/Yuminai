import SwiftUI
import YuminaiCore
import YuminaiUI

/// **ADR-117** — 커뮤니티 자료 독립 Sheet.
///
/// 기존에는 UserProfileSheet → "커뮤니티 자료" 섹션 안에만 있어 접근이 어려웠다.
/// ADR-117에서 사이드바 직접 진입점을 추가하면서, CommunityResourcesPanel을
/// 별도 Sheet로 감싸 onOpenCommunityResources 액션으로 바로 열 수 있도록 한다.
///
/// 크기: 860×640 — CommunityResourcesPanel의 넉넉한 표시 공간 확보.
struct CommunityResourcesSheet: View {

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // 헤더 바
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "cube.box.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Color.accent)
                Text("커뮤니티 자료")
                    .font(.system(size: 16, weight: .semibold))
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

            Divider()

            // 패널 본체 (스크롤 포함)
            ScrollView {
                CommunityResourcesPanel()
                    .environment(appModel)
                    .padding(Theme.Spacing.lg)
            }
        }
        .frame(width: 860, height: 640)
        .background(Theme.Color.bg)
    }
}
