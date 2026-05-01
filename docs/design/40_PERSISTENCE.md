# 40_PERSISTENCE — SwiftData 설계

> 모델 정의는 [`80_DATA_MODEL.md`](../prd/80_DATA_MODEL.md) 참조. 이 문서는 *어떻게 운영하는가*.

## ModelContainer 셋업

```swift
import SwiftData

public final class YuminaiModelContainer {
    public static let shared: ModelContainer = {
        let schema = Schema(YuminaiSchemaV1.models)
        let url = applicationSupportURL.appendingPathComponent("workspaces.store")
        let config = ModelConfiguration(
            schema: schema,
            url: url,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: YuminaiMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            // 마이그레이션 실패 = 사용자에게 경고 + 백업 복원 옵션
            fatalError("ModelContainer init failed: \(error)")
        }
    }()
    
    private static var applicationSupportURL: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Yuminai")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
```

## Context 사용 정책

SwiftData의 ModelContext는 thread-safe 하지 *않다*. Swift 6.2 환경에서 안전하게 쓰려면:

```swift
@MainActor
public final class MainContext {
    public static let shared = MainContext()
    public let context: ModelContext
    
    private init() {
        self.context = ModelContext(YuminaiModelContainer.shared)
    }
}

// 백그라운드 작업용 (별도 context)
public final actor PersistenceWorker {
    private let container: ModelContainer
    
    public init(container: ModelContainer = YuminaiModelContainer.shared) {
        self.container = container
    }
    
    public func perform<T: Sendable>(_ block: @Sendable (ModelContext) throws -> T) async throws -> T {
        let ctx = ModelContext(container)
        let result = try block(ctx)
        try ctx.save()
        return result
    }
}
```

## SwiftDataWorkspaceStore 구현

```swift
public final actor SwiftDataWorkspaceStore: WorkspaceStore {
    private let worker: PersistenceWorker
    
    public init(worker: PersistenceWorker = PersistenceWorker()) {
        self.worker = worker
    }
    
    public func list() async throws -> [Workspace] {
        try await worker.perform { ctx in
            let descriptor = FetchDescriptor<WorkspaceModel>(
                predicate: #Predicate { !$0.isArchived },
                sortBy: [SortDescriptor(\.lastOpenedAt, order: .reverse)]
            )
            return try ctx.fetch(descriptor).map(\.toCoreWorkspace)
        }
    }
    
    public func get(_ id: UUID) async throws -> Workspace? {
        try await worker.perform { ctx in
            let descriptor = FetchDescriptor<WorkspaceModel>(
                predicate: #Predicate { $0.id == id }
            )
            return try ctx.fetch(descriptor).first?.toCoreWorkspace
        }
    }
    
    public func create(_ workspace: Workspace) async throws {
        try await worker.perform { ctx in
            let model = WorkspaceModel(from: workspace)
            ctx.insert(model)
        }
    }
    
    // ...
}
```

## 모델 ↔ 도메인 변환

`@Model` 클래스(persistent)와 `Sendable struct`(domain)을 분리:

```swift
// YuminaiPersistence/Models/WorkspaceModel.swift
@Model
final class WorkspaceModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var directoryPath: String
    // ...
    
    init(from core: Workspace) {
        self.id = core.id
        self.name = core.name
        // ...
    }
    
    var toCoreWorkspace: Workspace {
        Workspace(id: id, name: name, directoryPath: directoryPath, createdAt: createdAt)
    }
}
```

이유:
- `@Model` 클래스는 Sendable 보장 안 됨 → actor 경계 못 넘음
- 도메인 struct는 Sendable + 불변 → 안전하게 전달

## 마이그레이션

### V1 (MVP-0)

```swift
public enum YuminaiSchemaV1: VersionedSchema {
    public static var versionIdentifier = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] = [
        WorkspaceModel.self, SessionModel.self, MessageModel.self, ToolEventModel.self
    ]
}
```

### V2 (예: 워크스페이스에 archived flag 추가 시)

```swift
public enum YuminaiSchemaV2: VersionedSchema {
    public static var versionIdentifier = Schema.Version(2, 0, 0)
    public static var models: [any PersistentModel.Type] = [
        WorkspaceModel.self, SessionModel.self, MessageModel.self, ToolEventModel.self
    ]
}

public enum YuminaiMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] = [
        YuminaiSchemaV1.self,
        YuminaiSchemaV2.self
    ]
    
    public static var stages: [MigrationStage] = [
        .lightweight(fromVersion: YuminaiSchemaV1.self, toVersion: YuminaiSchemaV2.self)
    ]
}
```

복잡한 변환 시 `.custom` stage:

```swift
.custom(
    fromVersion: YuminaiSchemaV1.self,
    toVersion: YuminaiSchemaV2.self,
    willMigrate: { context in
        // 백업
        try BackupManager.preMigrationBackup()
    },
    didMigrate: { context in
        // 데이터 변환
    }
)
```

## 백업 관리

```swift
public struct BackupManager: Sendable {
    public func backup(to url: URL? = nil) async throws -> URL {
        let backupRoot = applicationSupportURL.appendingPathComponent("backups")
        try FileManager.default.createDirectory(at: backupRoot, withIntermediateDirectories: true)
        
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let target = url ?? backupRoot.appendingPathComponent("\(timestamp).tar.gz")
        
        // tar로 store + workspaces/ 묶기
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = [
            "-czf", target.path,
            "-C", applicationSupportURL.path,
            "workspaces.store",
            "workspaces.store-shm",
            "workspaces.store-wal",
            "workspaces"
        ]
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw YuminaiError.sessionCorrupted(id: UUID(), reason: "backup failed")
        }
        
        return target
    }
    
    public func restore(from url: URL) async throws {
        // 1. 현재 store 임시 백업
        // 2. tar -xzf url 로 복원
        // 3. ModelContainer 재초기화 트리거
    }
    
    public func cleanup(olderThanDays: Int = 30) async throws {
        // 30일 이상 된 백업 삭제
    }
}
```

자동 백업 스케줄:
- 앱 시작 시 → 마지막 백업 > 24h이면 백그라운드 백업
- 마이그레이션 직전 강제 백업

## 쿼리 패턴

### 워크스페이스 리스트 (사이드바)

```swift
@MainActor
@Observable
final class WorkspaceListViewModel {
    var workspaces: [Workspace] = []
    private let store: WorkspaceStore
    
    init(store: WorkspaceStore) {
        self.store = store
    }
    
    func load() async {
        do {
            workspaces = try await store.list()
        } catch {
            // log + show error
        }
    }
}
```

### 세션 메시지 (페이지네이션)

큰 세션은 lazy 로딩:

```swift
public func messages(in sessionId: UUID, limit: Int = 50, before: Date? = nil) async throws -> [Message] {
    try await worker.perform { ctx in
        var descriptor = FetchDescriptor<MessageModel>(
            predicate: #Predicate { $0.session?.id == sessionId },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        if let before {
            descriptor.predicate = #Predicate {
                $0.session?.id == sessionId && $0.timestamp < before
            }
        }
        return try ctx.fetch(descriptor).map(\.toCoreMessage).reversed()
    }
}
```

## 인덱스

```swift
@Model
public final class MessageModel {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    // ...
    
    // SwiftData 6+ 인덱스 매크로
    #Index<MessageModel>([\.session, \.timestamp])
}
```

## 동시성 안전 체크리스트

- [ ] `@Model` 클래스는 actor 경계 넘지 않음 (struct 변환 후 전달)
- [ ] ModelContext는 생성한 thread/actor에서만 사용
- [ ] Background context는 별도 actor (`PersistenceWorker`)
- [ ] FetchDescriptor predicate는 `#Predicate` 매크로 (Sendable)
- [ ] `@Query`는 SwiftUI View에서만 (자동 MainActor)

## 테스트

### In-memory ModelContainer

```swift
extension ModelContainer {
    static func inMemory() -> ModelContainer {
        let schema = Schema(YuminaiSchemaV1.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }
}

@Test func createWorkspacePersists() async throws {
    let container = ModelContainer.inMemory()
    let store = SwiftDataWorkspaceStore(worker: PersistenceWorker(container: container))
    
    let ws = Workspace(id: UUID(), name: "test", directoryPath: "/tmp")
    try await store.create(ws)
    
    let fetched = try await store.list()
    #expect(fetched.contains(where: { $0.id == ws.id }))
}
```

## 성능 노트

- 메시지 1만 개 / 워크스페이스 → 사이드바 로딩 < 100ms 목표
- 무한 스크롤은 fetchLimit + before 패턴
- 검색은 SQLite FTS (`SwiftData`는 직접 지원 안 함 → v0.3에서 GRDB 평가)

## 알려진 한계

- SwiftData는 fully relational X (관계 쿼리 제약)
- 마이그레이션 디버깅 도구가 약함
- iCloud 통합은 v0.3+ 검토 (`cloudKitDatabase`)

→ 한계 확인 시 [`docs/log/42_DECISIONS.md`](../log/42_DECISIONS.md)에 GRDB 전환 검토 기록.
