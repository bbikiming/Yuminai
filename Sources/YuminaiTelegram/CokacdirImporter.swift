import Foundation

/// `cokacdir` (https://cokacdir.cokac.com/)의 `~/.cokacdir/workspace/bot_settings.json`에서
/// Telegram 봇 설정을 import. 토큰을 사용자가 다시 입력할 필요 없음.
///
/// `cokacdir`은 Telegram bot server를 자체 실행 (`--ccserver <TOKEN>`)하므로,
/// 이 import는 *토큰 공유* 목적이지 cokacdir CLI에 위임하는 게 아님.
/// 같은 토큰으로 Yuminai와 cokacdir의 폴링이 동시 실행되면 Telegram update 분산 문제가
/// 생긴다 — 사용자에게 Setting UI에서 안내한다.
public struct CokacdirImporter: Sendable {
    public let botSettingsPath: String

    public init(botSettingsPath: String) {
        self.botSettingsPath = botSettingsPath
    }

    public func loadBots() async throws -> [CokacdirBot] {
        let url = URL(fileURLWithPath: botSettingsPath)
        guard FileManager.default.fileExists(atPath: botSettingsPath) else {
            throw CokacdirImportError.notFound(path: botSettingsPath)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw CokacdirImportError.readFailed(error.localizedDescription)
        }
        return try Self.parse(data: data)
    }

    /// bot_settings.json 형식:
    /// `{ "<bot-hash>": { "display_name": ..., "username": ..., "token": ..., "owner_user_id": ..., "last_sessions": { "<chat-id>": "<workspace-path>" } } }`
    static func parse(data: Data) throws -> [CokacdirBot] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CokacdirImportError.invalidJSON
        }
        var bots: [CokacdirBot] = []
        for (hash, raw) in json {
            guard let dict = raw as? [String: Any] else { continue }
            guard let token = dict["token"] as? String, !token.isEmpty else { continue }
            let displayName = (dict["display_name"] as? String) ?? "Bot \(hash.prefix(8))"
            let username = (dict["username"] as? String) ?? ""
            let ownerUserId = coerceInt64(dict["owner_user_id"]) ?? 0
            let suggestedChatIds: [Int64] = parseSuggestedChats(dict["last_sessions"])

            bots.append(CokacdirBot(
                botHash: hash,
                displayName: displayName,
                username: username,
                token: token,
                ownerUserId: ownerUserId,
                suggestedChatIds: suggestedChatIds
            ))
        }
        // display_name 알파벳 순
        return bots.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private static func parseSuggestedChats(_ any: Any?) -> [Int64] {
        guard let dict = any as? [String: Any] else { return [] }
        var ids: [Int64] = []
        for key in dict.keys {
            if let id = Int64(key) {
                ids.append(id)
            }
        }
        // owner positive id 우선, 그 다음 group/channel negative id
        return ids.sorted { abs($0) < abs($1) }
    }

    private static func coerceInt64(_ any: Any?) -> Int64? {
        if let v = any as? Int64 { return v }
        if let v = any as? Int { return Int64(v) }
        if let v = any as? NSNumber { return v.int64Value }
        if let s = any as? String { return Int64(s) }
        return nil
    }
}

/// cokacdir bot_settings.json에서 import한 단일 봇 정보. UI 모듈에서도 사용.
public struct CokacdirBot: Sendable, Equatable, Identifiable, Hashable {
    public let botHash: String
    public let displayName: String
    public let username: String
    public let token: String
    public let ownerUserId: Int64
    /// last_sessions 키에서 추출한 chat id 후보들 (양수 = 1:1, 음수 = group/channel).
    public let suggestedChatIds: [Int64]

    public var id: String { botHash }

    public init(
        botHash: String,
        displayName: String,
        username: String,
        token: String,
        ownerUserId: Int64,
        suggestedChatIds: [Int64]
    ) {
        self.botHash = botHash
        self.displayName = displayName
        self.username = username
        self.token = token
        self.ownerUserId = ownerUserId
        self.suggestedChatIds = suggestedChatIds
    }

    /// `@username` (cokacdir bot username 필드).
    public var handle: String {
        username.isEmpty ? botHash : "@\(username)"
    }
}

/// 텔레그램 chat의 사람-친화 라벨. CokacdirChatInspector가 group_chat 로그에서 추출.
public struct CokacdirChatLabel: Sendable, Equatable, Hashable {
    public let chatId: Int64
    public let kind: Kind
    public let title: String
    public let participantNames: [String]

    public enum Kind: String, Sendable {
        case directWithOwner    // 1:1 (positive id == owner_user_id)
        case directOther        // 1:1 (positive id, 다른 사람)
        case group              // negative id, 그룹
        case unknown
    }

    public init(chatId: Int64, kind: Kind, title: String, participantNames: [String] = []) {
        self.chatId = chatId
        self.kind = kind
        self.title = title
        self.participantNames = participantNames
    }
}

/// `~/.cokacdir/group_chat/<chat_id>.jsonl` 로그를 읽어 사람/봇 이름을 추출.
/// CokacdirImportSheet에서 chat chip에 친화적 라벨 표시.
public struct CokacdirChatInspector: Sendable {
    public let groupChatDir: String

    public init(groupChatDir: String = CokacdirChatInspector.defaultDir()) {
        self.groupChatDir = groupChatDir
    }

    public static func defaultDir() -> String {
        NSString(string: "~/.cokacdir/group_chat").expandingTildeInPath
    }

    public func label(for chatId: Int64, ownerUserId: Int64) async -> CokacdirChatLabel {
        let kind: CokacdirChatLabel.Kind
        if chatId > 0 {
            kind = (chatId == ownerUserId) ? .directWithOwner : .directOther
        } else {
            kind = .group
        }

        let logPath = "\(groupChatDir)/\(chatId).jsonl"
        let participants = Self.extractParticipants(from: logPath, limit: 200)

        let title: String
        switch kind {
        case .directWithOwner:
            title = "내 1:1 채팅"
        case .directOther:
            let other = participants.first(where: { !$0.contains(String(ownerUserId)) }) ?? "다른 사람"
            title = "1:1 — \(other)"
        case .group:
            let bots = participants.filter { $0.hasPrefix("🤖 ") }
            let humans = participants.filter { !$0.hasPrefix("🤖 ") && $0 != "system" }
            if !bots.isEmpty && !humans.isEmpty {
                let names = (bots + humans).prefix(3).joined(separator: ", ")
                title = "그룹 — \(names)"
            } else if !bots.isEmpty {
                title = "그룹 (봇 \(bots.count)개)"
            } else {
                title = "그룹 채팅"
            }
        case .unknown:
            title = "알 수 없음"
        }

        return CokacdirChatLabel(
            chatId: chatId,
            kind: kind,
            title: title,
            participantNames: participants
        )
    }

    /// jsonl을 line-by-line 파싱해 from/bot_display_name 추출 (중복 제거 + max limit).
    static func extractParticipants(from path: String, limit: Int) -> [String] {
        guard let data = try? String(contentsOfFile: path, encoding: .utf8) else {
            return []
        }
        var seen = Set<String>()
        var ordered: [String] = []
        for line in data.split(separator: "\n", omittingEmptySubsequences: true) {
            if ordered.count >= limit { break }
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }

            // bot_display_name → "🤖 <name>"
            if let botName = json["bot_display_name"] as? String, !botName.isEmpty {
                let label = "🤖 \(botName)"
                if seen.insert(label).inserted { ordered.append(label) }
            }
            // from → "김유석(123)" 또는 "bot:other_bot" 또는 nil
            if let from = json["from"] as? String, !from.isEmpty, !from.hasPrefix("bot:") {
                if seen.insert(from).inserted { ordered.append(from) }
            }
        }
        return ordered
    }
}

public enum CokacdirImportError: Error, LocalizedError, Sendable {
    case notFound(path: String)
    case readFailed(String)
    case invalidJSON

    public var errorDescription: String? {
        switch self {
        case .notFound(let path):
            return "cokacdir bot 설정을 찾지 못했어요: \(path)"
        case .readFailed(let reason):
            return "bot_settings.json 읽기 실패: \(reason)"
        case .invalidJSON:
            return "bot_settings.json 형식이 예상과 달라요."
        }
    }
}
