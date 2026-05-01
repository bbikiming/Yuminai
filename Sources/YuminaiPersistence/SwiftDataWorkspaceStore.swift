import Foundation
import SwiftData
import YuminaiCore

/// SwiftData 기반 `WorkspaceStore`.
///
/// 매 작업마다 새 `ModelContext`를 만들어 단순성/격리를 우선한다. 본인 1인 사용 규모에서 충분.
public final actor SwiftDataWorkspaceStore: WorkspaceStore {
    private let container: ModelContainer

    public init(container: ModelContainer) {
        self.container = container
    }

    public func list() async throws -> [Workspace] {
        let ctx = ModelContext(container)
        let descriptor = FetchDescriptor<WorkspaceModel>(
            sortBy: [SortDescriptor(\.lastOpenedAt, order: .reverse)]
        )
        return try ctx.fetch(descriptor)
            .filter { !$0.isArchived }
            .map(\.toCoreWorkspace)
    }

    public func get(_ id: UUID) async throws -> Workspace? {
        let ctx = ModelContext(container)
        let descriptor = FetchDescriptor<WorkspaceModel>(
            predicate: #Predicate { $0.id == id }
        )
        return try ctx.fetch(descriptor).first?.toCoreWorkspace
    }

    public func create(_ workspace: Workspace) async throws {
        let ctx = ModelContext(container)
        let id = workspace.id
        let dupDesc = FetchDescriptor<WorkspaceModel>(
            predicate: #Predicate { $0.id == id }
        )
        if try !ctx.fetch(dupDesc).isEmpty {
            throw YuminaiError.workspaceAlreadyExists(name: workspace.name)
        }
        ctx.insert(WorkspaceModel(from: workspace))
        try ctx.save()
    }

    public func update(_ workspace: Workspace) async throws {
        let ctx = ModelContext(container)
        let id = workspace.id
        let descriptor = FetchDescriptor<WorkspaceModel>(
            predicate: #Predicate { $0.id == id }
        )
        guard let model = try ctx.fetch(descriptor).first else {
            throw YuminaiError.workspaceNotFound(id: workspace.id)
        }
        model.name = workspace.name
        model.directoryPath = workspace.directoryPath
        model.lastOpenedAt = workspace.lastOpenedAt
        model.harnessTemplateRaw = workspace.harnessTemplate?.rawValue
        model.isArchived = workspace.isArchived
        try ctx.save()
    }

    public func delete(_ id: UUID) async throws {
        let ctx = ModelContext(container)
        let descriptor = FetchDescriptor<WorkspaceModel>(
            predicate: #Predicate { $0.id == id }
        )
        guard let model = try ctx.fetch(descriptor).first else {
            return
        }
        ctx.delete(model)
        try ctx.save()
    }
}
