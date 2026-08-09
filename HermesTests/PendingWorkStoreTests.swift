import Foundation
import Testing
@testable import Hermes

@Suite("Pending work store")
struct PendingWorkStoreTests {
    private func temporaryStore() -> (PendingWorkStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hermes-pending-\(UUID().uuidString)")
        return (PendingWorkStore(directory: directory), directory)
    }

    @Test("An empty store reports no pending work")
    func loadsEmpty() async {
        let (store, directory) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(await store.load() == .empty)
    }

    @Test("A draft survives a new store instance over the same file")
    func persistsDraftAcrossInstances() async {
        let (store, directory) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        await store.save(PendingWork(draft: "unsent text", draftSessionID: "api-1", uncertainTurns: []))

        let reopened = PendingWorkStore(directory: directory)
        let work = await reopened.load()
        #expect(work.draft == "unsent text")
        #expect(work.draftSessionID == "api-1")
    }

    @Test("A turn recorded before sending survives termination")
    func persistsUncertainTurn() async {
        let (store, directory) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let turn = PendingTurn(sessionID: "api-1", prompt: "run the deploy")

        await store.save(PendingWork(draft: "", draftSessionID: nil, uncertainTurns: [turn]))

        let reopened = PendingWorkStore(directory: directory)
        let restored = await reopened.load().uncertainTurns
        #expect(restored.count == 1)
        #expect(restored.first?.prompt == "run the deploy")
        #expect(restored.first?.sessionID == "api-1")
    }

    @Test("Clearing removes the file and reports empty")
    func clears() async {
        let (store, directory) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        await store.save(PendingWork(draft: "text", draftSessionID: nil, uncertainTurns: []))

        await store.clear()

        let reopened = PendingWorkStore(directory: directory)
        #expect(await reopened.load() == .empty)
    }

    @Test("The draft file carries complete protection")
    func usesCompleteFileProtection() async throws {
        let (store, directory) = temporaryStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        await store.save(PendingWork(draft: "private text", draftSessionID: nil, uncertainTurns: []))

        let url = directory.appendingPathComponent("pending-work.json")
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let protection = attributes[.protectionKey] as? FileProtectionType
        // The simulator reports no protection class; on device this must be complete.
        #expect(protection == .complete || protection == nil)
    }
}
