import Foundation

/// A turn recorded before network I/O so an interruption can be resolved later.
nonisolated struct PendingTurn: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    var sessionID: String?
    var prompt: String
    var createdAt: Date

    init(id: UUID = UUID(), sessionID: String?, prompt: String, createdAt: Date = .now) {
        self.id = id
        self.sessionID = sessionID
        self.prompt = prompt
        self.createdAt = createdAt
    }
}

/// Work that exists only on the device: text the user has not sent, and turns
/// whose outcome the app has not yet confirmed.
nonisolated struct PendingWork: Codable, Sendable, Equatable {
    var draft: String = ""
    var draftSessionID: String?
    var uncertainTurns: [PendingTurn] = []

    static let empty = PendingWork()
}

protocol PendingWorkStoring: Sendable {
    func load() async -> PendingWork
    func save(_ work: PendingWork) async
    func clear() async
}

/// File-backed store for pending work.
///
/// Drafts are user content, so the file uses complete protection and is written
/// atomically. Nothing here is a credential.
actor PendingWorkStore: PendingWorkStoring {
    private let url: URL
    private var cached: PendingWork?

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.url = base.appendingPathComponent("pending-work.json")
    }

    func load() -> PendingWork {
        if let cached { return cached }
        guard let data = try? Data(contentsOf: url),
              let work = try? JSONDecoder().decode(PendingWork.self, from: data) else {
            return .empty
        }
        cached = work
        return work
    }

    func save(_ work: PendingWork) {
        cached = work
        guard let data = try? JSONEncoder().encode(work) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    func clear() {
        cached = .empty
        try? FileManager.default.removeItem(at: url)
    }
}
