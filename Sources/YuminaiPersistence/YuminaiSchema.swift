import Foundation
import SwiftData

/// Yuminai의 첫 번째 schema 버전. 이후 변경은 새 `VersionedSchema` 추가 + `MigrationStage`.
public enum YuminaiSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [WorkspaceModel.self, SessionModel.self, MessageModel.self]
    }
}

public enum YuminaiMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [YuminaiSchemaV1.self]
    }

    public static var stages: [MigrationStage] {
        []
    }
}

public enum YuminaiModelContainerFactory {
    /// 사용자 영구 저장 컨테이너. `~/Library/Application Support/Yuminai/workspaces.store`.
    public static func live() throws -> ModelContainer {
        let schema = Schema(YuminaiSchemaV1.models)
        let url = try liveStoreURL()
        let config = ModelConfiguration(
            schema: schema,
            url: url,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: YuminaiMigrationPlan.self,
            configurations: [config]
        )
    }

    /// In-memory 컨테이너. 단위 테스트 전용.
    public static func inMemory() throws -> ModelContainer {
        let schema = Schema(YuminaiSchemaV1.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    public static func liveStoreURL() throws -> URL {
        let fm = FileManager.default
        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let yuminaiDir = appSupport.appendingPathComponent("Yuminai", isDirectory: true)
        try fm.createDirectory(at: yuminaiDir, withIntermediateDirectories: true)
        return yuminaiDir.appendingPathComponent("workspaces.store")
    }
}
