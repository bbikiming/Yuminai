import Foundation

/// 앱이 참조하는 외부 URL 모음 — 한 곳에서 관리.
public enum AppLinks {
    /// Yuminai 사용자 가이드 (웹).
    public static let userGuide: URL = URL(string: "https://yuminai-guide.vercel.app/")!

    /// BotFather (텔레그램 봇 생성).
    public static let botFather: URL = URL(string: "https://t.me/botfather")!

    /// Telegram Bot API 공식 문서.
    public static let telegramBotAPI: URL = URL(string: "https://core.telegram.org/bots/api")!
}
