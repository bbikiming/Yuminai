import Foundation

// MARK: - ChatBindingAuditLog (ADR-061 Phase 4)

/// 멀티 chat binding 변경의 audit log.
///
/// **저장**: NDJSON file (`~/Library/Application Support/Yuminai/chat-bindings/audit.ndjson`)
/// **회고**: 누가 언제 어떤 chat을 어느 워크스페이스에 binding했는지 (책임 추적).
public actor ChatBindingAuditLog {
    public static let directoryURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSString(string: "~/Library/Application Support").expandingTildeInPath)
        return appSupport.appendingPathComponent("Yuminai/chat-bindings", isDirectory: true)
    }()

    public static let auditFileName = "audit.ndjson"
    public static let memoryCap = 500

    private let directoryURL: URL
    private(set) var entries: [ChatBindingAuditEntry] = []

    public init(directoryURL: URL = ChatBindingAuditLog.directoryURL) {
        self.directoryURL = directoryURL
        // load — actor 격리 외부에서 sync 호출 (init 내부)
        let url = directoryURL.appendingPathComponent(Self.auditFileName)
        if FileManager.default.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url),
           let str = String(data: data, encoding: .utf8) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            for line in str.split(separator: "\n") {
                if let d = line.data(using: .utf8),
                   let entry = try? decoder.decode(ChatBindingAuditEntry.self, from: d) {
                    self.entries.append(entry)
                }
            }
            if self.entries.count > Self.memoryCap {
                self.entries = Array(self.entries.suffix(Self.memoryCap))
            }
        }
    }

    /// 새 binding 변경 기록.
    public func record(_ entry: ChatBindingAuditEntry) {
        entries.append(entry)
        // memory cap
        if entries.count > Self.memoryCap {
            entries = Array(entries.suffix(Self.memoryCap))
        }
        persist(entry)
    }

    /// 최근 N개 entries (UI binding용).
    public func recent(limit: Int = 50) -> [ChatBindingAuditEntry] {
        Array(entries.suffix(limit).reversed())
    }

    public func snapshot() -> [ChatBindingAuditEntry] { entries }

    // MARK: - Internal

    private func persist(_ entry: ChatBindingAuditEntry) {
        do {
            let fm = FileManager.default
            if !fm.fileExists(atPath: directoryURL.path) {
                try fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            }
            let url = directoryURL.appendingPathComponent(Self.auditFileName)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            var line = try encoder.encode(entry)
            line.append(0x0A)
            if fm.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } else {
                try line.write(to: url, options: .atomic)
                try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            }
        } catch {
            #if DEBUG
            print("[ChatBindingAuditLog] persist failed: \(error)")
            #endif
        }
    }
}

public struct ChatBindingAuditEntry: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let timestamp: Date
    public let chatId: Int64
    public let userId: Int64
    public let action: Action
    public let workspaceId: UUID?
    public let workspaceName: String?

    public enum Action: String, Codable, Sendable, Hashable {
        case bind
        case unbind
        case rebind  // 같은 chat이 다른 workspace로 변경
    }

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        chatId: Int64,
        userId: Int64,
        action: Action,
        workspaceId: UUID?,
        workspaceName: String?
    ) {
        self.id = id
        self.timestamp = timestamp
        self.chatId = chatId
        self.userId = userId
        self.action = action
        self.workspaceId = workspaceId
        self.workspaceName = workspaceName
    }
}
