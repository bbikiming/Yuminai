import SwiftUI

/// **ADR-068** — Yuminai Brand Logo (in-app SwiftUI render).
///
/// SVG와 동일한 디자인을 SwiftUI Shapes로 재현 — Asset 의존 없이 vector render.
/// 모든 크기에서 깨끗한 vector 출력. macOS Big Sur+ squircle 스펙 호환.
public struct BrandLogo: View {
    public let size: CGFloat

    public init(size: CGFloat = 128) {
        self.size = size
    }

    public var body: some View {
        ZStack {
            // 1. Background squircle with gradient
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(LinearGradient(
                    colors: [
                        Color(red: 0.06, green: 0.66, blue: 0.75),  // #0FA8C0
                        Color(red: 0.13, green: 0.78, blue: 0.88),  // #22C8E0
                        Color(red: 0.36, green: 0.85, blue: 0.93)   // #5BD9EE
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            // 2. Inner subtle highlight
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(RadialGradient(
                    colors: [Color.white.opacity(0.18), Color.white.opacity(0)],
                    center: .init(x: 0.5, y: 0.35),
                    startRadius: 0,
                    endRadius: size * 0.6
                ))

            // 3. Convergence glyph — top 3 dots → bottom 1 dot
            convergenceGlyph
                .padding(size * 0.15)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.15), radius: size * 0.04, x: 0, y: size * 0.02)
    }

    private var convergenceGlyph: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let dotR: CGFloat = w * 0.085
            let centerDotR: CGFloat = w * 0.105
            let bottomDotR: CGFloat = w * 0.135

            ZStack {
                // Convergence lines (먼저 그려서 dot 뒤로)
                Path { path in
                    // 좌상 → 중하
                    path.move(to: CGPoint(x: w * 0.36, y: h * 0.40))
                    path.addQuadCurve(
                        to: CGPoint(x: w * 0.50, y: h * 0.86),
                        control: CGPoint(x: w * 0.45, y: h * 0.70)
                    )
                    // 중상 → 중하
                    path.move(to: CGPoint(x: w * 0.50, y: h * 0.36))
                    path.addLine(to: CGPoint(x: w * 0.50, y: h * 0.86))
                    // 우상 → 중하
                    path.move(to: CGPoint(x: w * 0.64, y: h * 0.40))
                    path.addQuadCurve(
                        to: CGPoint(x: w * 0.50, y: h * 0.86),
                        control: CGPoint(x: w * 0.55, y: h * 0.70)
                    )
                }
                .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: w * 0.022, lineCap: .round))

                // Top 3 dots (multi-agent)
                Circle()
                    .fill(Color.white)
                    .frame(width: dotR * 2, height: dotR * 2)
                    .position(x: w * 0.36, y: h * 0.34)

                Circle()
                    .fill(Color.white)
                    .frame(width: centerDotR * 2, height: centerDotR * 2)
                    .position(x: w * 0.50, y: h * 0.30)

                Circle()
                    .fill(Color.white)
                    .frame(width: dotR * 2, height: dotR * 2)
                    .position(x: w * 0.64, y: h * 0.34)

                // Bottom convergence dot (unified conversation)
                Circle()
                    .fill(Color.white)
                    .frame(width: bottomDotR * 2, height: bottomDotR * 2)
                    .position(x: w * 0.50, y: h * 0.86)

                // Center accent (cyan dot inside bottom)
                Circle()
                    .fill(LinearGradient(
                        colors: [
                            Color(red: 0.06, green: 0.66, blue: 0.75),
                            Color(red: 0.13, green: 0.78, blue: 0.88)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .frame(width: bottomDotR * 0.7, height: bottomDotR * 0.7)
                    .position(x: w * 0.50, y: h * 0.86)
            }
        }
    }
}

#Preview {
    HStack(spacing: 24) {
        BrandLogo(size: 64)
        BrandLogo(size: 128)
        BrandLogo(size: 256)
    }
    .padding()
    .background(Color.gray.opacity(0.1))
}
