import SwiftUI

/// **ADR-068 Phase 3** — Splash screen (첫 실행 시 brand mark + 로딩 애니메이션).
///
/// 표시 정책:
/// - 첫 실행 시: 2초 표시
/// - 이후 실행: 0.8초 (빠른 인지 + 짧은 fade out)
/// - 사용자 클릭 시 즉시 dismiss
public struct SplashScreen: View {
    public let isFirstLaunch: Bool
    public let onDismiss: () -> Void

    @State private var logoScale: CGFloat = 0.6
    @State private var logoOpacity: Double = 0
    @State private var taglineOpacity: Double = 0

    public init(isFirstLaunch: Bool = false, onDismiss: @escaping () -> Void) {
        self.isFirstLaunch = isFirstLaunch
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            // Background — full window cyan gradient
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.66, blue: 0.75),
                    Color(red: 0.13, green: 0.78, blue: 0.88),
                    Color(red: 0.36, green: 0.85, blue: 0.93)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                // Logo (큰 사이즈, 애니메이션)
                BrandLogo(size: 180)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)

                // App name
                Text("Yuminai")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(.white)
                    .opacity(taglineOpacity)

                // Tagline
                Text("다중 LLM vibe-coding workspace")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.85))
                    .opacity(taglineOpacity)

                if isFirstLaunch {
                    Text("처음 시작합니다…")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                        .opacity(taglineOpacity)
                        .padding(.top, 12)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .onAppear {
            // Logo entry animation
            withAnimation(.spring(response: 0.7, dampingFraction: 0.7)) {
                logoScale = 1.0
                logoOpacity = 1
            }
            withAnimation(.easeIn(duration: 0.4).delay(0.3)) {
                taglineOpacity = 1
            }
            // Auto dismiss
            let delay: Double = isFirstLaunch ? 2.0 : 0.8
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                onDismiss()
            }
        }
    }
}
