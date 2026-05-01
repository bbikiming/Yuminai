import SwiftUI

/// Yuminai 디자인 토큰. 직접 `.font(.system(size: 13))` 같은 호출 대신 항상 이 토큰을 거친다.
public enum Theme {
    public enum Color {
        public static let label = SwiftUI.Color.primary
        public static let labelSecondary = SwiftUI.Color.secondary

        // Claude orange — 정확한 값은 디자인 단계에서 보정
        public static let accent = SwiftUI.Color(red: 0.85, green: 0.55, blue: 0.30)
        public static let success = SwiftUI.Color(red: 0.30, green: 0.80, blue: 0.50)
        public static let warning = SwiftUI.Color(red: 0.95, green: 0.75, blue: 0.20)
        public static let error = SwiftUI.Color(red: 0.95, green: 0.30, blue: 0.30)
    }

    public enum Typography {
        public static let body = Font.system(.body, design: .default)
        public static let bodyMono = Font.system(.body, design: .monospaced)
        public static let chatMessage = Font.system(size: 13, design: .monospaced)
        public static let chatInput = Font.system(size: 13, design: .monospaced)
        public static let codeBlock = Font.system(size: 12, design: .monospaced)
        public static let label = Font.system(.callout, design: .default)
    }

    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
    }

    public enum Radius {
        public static let sm: CGFloat = 4
        public static let md: CGFloat = 8
        public static let lg: CGFloat = 12
    }
}
