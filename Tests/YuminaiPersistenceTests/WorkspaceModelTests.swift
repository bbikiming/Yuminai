import Foundation
import Testing
import SwiftData
import YuminaiCore
@testable import YuminaiPersistence

@Suite("WorkspaceModel ↔ Workspace round-trip")
struct WorkspaceModelTests {
    @Test("도메인 → 영속 → 도메인 변환이 손실 없이 동작한다")
    func roundTripPreservesFields() {
        let original = Workspace(
            id: UUID(),
            name: "round-trip",
            directoryPath: "/tmp/rt",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastOpenedAt: Date(timeIntervalSince1970: 1_700_001_000),
            harnessTemplate: .swift,
            isArchived: true
        )

        let persisted = WorkspaceModel(from: original)
        let recovered = persisted.toCoreWorkspace

        #expect(recovered.id == original.id)
        #expect(recovered.name == original.name)
        #expect(recovered.directoryPath == original.directoryPath)
        #expect(recovered.createdAt == original.createdAt)
        #expect(recovered.lastOpenedAt == original.lastOpenedAt)
        #expect(recovered.harnessTemplate == original.harnessTemplate)
        #expect(recovered.isArchived == original.isArchived)
    }

    @Test("In-memory ModelContainer가 정상 셋업된다")
    func inMemoryContainerInitializes() throws {
        let container = try YuminaiModelContainerFactory.inMemory()
        let context = ModelContext(container)
        let model = WorkspaceModel(
            from: Workspace(name: "x", directoryPath: "/x")
        )
        context.insert(model)
        try context.save()

        let descriptor = FetchDescriptor<WorkspaceModel>()
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "x")
    }
}
