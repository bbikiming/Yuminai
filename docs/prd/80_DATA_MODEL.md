# 80_DATA_MODEL — 데이터 모델

> SwiftData 기반. Migration은 `SchemaMigrationPlan`으로 관리.

## 저장 위치

```
~/Library/Application Support/Yuminai/
├── workspaces.store         ← SwiftData 메인 store
├── workspaces.store-shm
├── workspaces.store-wal
├── secrets/                 ← (시크릿은 Keychain. 여긴 메타데이터 인덱스만)
└── logs/
    └── 2026-05-01.log
```

## SwiftData 엔티티 (MVP-0)

```swift
import SwiftData

@Model
public final class Workspace {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var directoryPath: String          // 절대 경로
    public var createdAt: Date
    public var lastOpenedAt: Date?
    public var harnessTemplate: String?       // "swift" | "typescript" | "python" | "general" | nil
    public var isArchived: Bool
    
    @Relationship(deleteRule: .cascade, inverse: \Session.workspace)
    public var sessions: [Session]
    
    public init(id: UUID = UUID(), name: String, directoryPath: String, harnessTemplate: String? = nil) {
        self.id = id
        self.name = name
        self.directoryPath = directoryPath
        self.createdAt = Date()
        self.harnessTemplate = harnessTemplate
        self.isArchived = false
        self.sessions = []
    }
}

@Model
public final class Session {
    @Attribute(.unique) public var id: UUID
    public var startedAt: Date
    public var endedAt: Date?
    public var title: String?                 // 첫 사용자 메시지 자동 요약
    public var workspace: Workspace?
    
    @Relationship(deleteRule: .cascade, inverse: \Message.session)
    public var messages: [Message]
    
    public init(id: UUID = UUID(), workspace: Workspace? = nil) {
        self.id = id
        self.startedAt = Date()
        self.workspace = workspace
        self.messages = []
    }
}

@Model
public final class Message {
    @Attribute(.unique) public var id: UUID
    public var timestamp: Date
    public var role: Role.RawValue            // user | assistant | system | tool
    public var content: String                // 평문(ANSI 제거)
    public var rawANSI: String?               // 원본 ANSI 보존(필요시)
    public var session: Session?
    
    public enum Role: String, Codable, Sendable {
        case user, assistant, system, tool
    }
    
    public init(id: UUID = UUID(), role: Role, content: String, rawANSI: String? = nil) {
        self.id = id
        self.timestamp = Date()
        self.role = role.rawValue
        self.content = content
        self.rawANSI = rawANSI
    }
}

@Model
public final class ToolEvent {
    @Attribute(.unique) public var id: UUID
    public var timestamp: Date
    public var toolName: String               // "Read" | "Edit" | "Bash" | ...
    public var input: String                  // JSON 직렬화
    public var output: String?
    public var success: Bool
    public var session: Session?
    
    public init(id: UUID = UUID(), toolName: String, input: String, output: String?, success: Bool) {
        self.id = id
        self.timestamp = Date()
        self.toolName = toolName
        self.input = input
        self.output = output
        self.success = success
    }
}
```

## v0.2 추가 엔티티

```swift
@Model
public final class ObsidianNoteRef {
    @Attribute(.unique) public var id: UUID
    public var vaultPath: String              // 상대 경로 (vault root 기준)
    public var lastIndexedAt: Date
    public var bodyHash: String               // 변경 감지
}

@Model
public final class TelegramAlert {
    @Attribute(.unique) public var id: UUID
    public var sentAt: Date
    public var workspaceId: UUID
    public var sessionId: UUID?
    public var category: String               // "complete" | "error" | "decision"
    public var message: String
    public var responseReceivedAt: Date?
    public var responsePayload: String?
}
```

## 인덱스

```swift
@Model
public final class Message { ... }
// SwiftData가 @Attribute(.unique)에 인덱스 생성
// 추가 인덱스가 필요하면 #Index 사용 (Swift 6.2):
//   #Index<Message>([\.timestamp], [\.session, \.timestamp])
```

권장 인덱스:
- `Message`: `(session, timestamp)` 복합 — 세션별 시간순 조회
- `Session`: `(workspace, startedAt)` 복합
- `ObsidianNoteRef`: `(vaultPath)` — 단일

## 마이그레이션 정책

```swift
public enum YuminaiSchemaV1: VersionedSchema {
    public static var versionIdentifier = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] = [
        Workspace.self, Session.self, Message.self, ToolEvent.self
    ]
}

public enum YuminaiMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] = [YuminaiSchemaV1.self]
    public static var stages: [MigrationStage] = []
}
```

향후 v2에서 변경 시:
- `lightweight` 마이그레이션 우선 (필드 추가)
- `custom` 마이그레이션은 데이터 변환 필요 시
- 매 schema 변경 전 백업: `~/Library/Application Support/Yuminai/backups/{date}.store`

## 파일 시스템 데이터 (DB 외)

```
~/Library/Application Support/Yuminai/
└── workspaces/
    └── {workspace-id}/
        ├── .harness/                   ← 사용자 워크스페이스 하네스 (claude-forge 패턴)
        │   ├── rules/
        │   ├── agents/
        │   ├── skills/
        │   ├── hooks/
        │   ├── commands/
        │   ├── settings.json
        │   └── .mcp.json
        ├── attachments/                ← 채팅 첨부 (이미지 등 — v0.3)
        └── exports/                    ← 노트 export 임시
```

## Keychain 항목

```
Service: com.yuminai
Account:
  - anthropic_api_key             (옵션 — Claude Code OAuth 시 불필요)
  - telegram_bot_token            (옵션)
  - telegram_allowed_user_id      (옵션)
  - obsidian_vault_path           (시크릿은 아니지만 위치 보호)
  - mcp_server_{name}_token       (워크스페이스별)
```

## 데이터 크기 추정

| 메시지 1만 개 | ~ 30MB (평균 3KB) |
| 워크스페이스 5개 | ~ 150MB |
| ToolEvent 5만 개 | ~ 100MB |

> SwiftData가 1GB 넘기 전엔 성능 문제 거의 없음. 그 이상 갈 일 1년 내 없을 듯.

## 백업/복원

- 자동: 일 1회 `~/Library/Application Support/Yuminai/backups/{YYYY-MM-DD}.tar.gz`
- 30일 보관, 그 후 삭제
- 복원: 설정 화면에서 백업 선택 → 앱 재시작
- iCloud 동기화 옵션은 v0.3+ (메타만)

## GDPR / 개인정보

본인 사용이지만 원칙:
- 모든 데이터 로컬, 외부 전송 없음
- 삭제 = SwiftData에서 cascade delete + 파일 시스템 정리
- 외부 API(Anthropic, Telegram) 전송은 사용자가 명시적으로 트리거
