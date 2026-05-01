import Foundation
import SwiftData

/// Yuminai의 첫 번째 schema 버전. 이후 변경은 새 `VersionedSchema` 추가 + `MigrationStage`.
public enum YuminaiSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [WorkspaceModel.self]
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
    /// In-memory 컨테이너. 단위 테스트 전용.
    public static func inMemory() throws -> ModelContainer {
        let schema = Schema(YuminaiSchemaV1.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
