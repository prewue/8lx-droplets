import Foundation

/// A job K*llTree stopped, and whether launchd had it loaded at the time:
/// only those are loaded again on the way back.
struct StoppedJob: Codable, Sendable, Hashable {
    let job: LaunchJob
    let wasLoaded: Bool
}

/// A vendor K*llTree closed and keeps closed until one of its apps opens.
struct ClosedGroup: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let iconPath: String?
    let jobs: [StoppedJob]
    /// The jobs were also disabled, so they stay off after a restart.
    let persisted: Bool
    let closedAt: Date
    let processCount: Int
    let freedMemory: UInt64
    /// Background processes started again and closed again since.
    var reclosed: Int = 0
}

struct JournalEntry: Codable, Sendable, Identifiable, Hashable {
    enum Kind: String, Codable, Sendable {
        case closed, restored, reclosed, refused, note
    }

    var id = UUID()
    let date: Date
    let kind: Kind
    let text: String

    var symbol: String {
        switch kind {
        case .closed: return "xmark.circle.fill"
        case .restored: return "arrow.uturn.backward.circle.fill"
        case .reclosed: return "shield.lefthalf.filled"
        case .refused: return "exclamationmark.triangle.fill"
        case .note: return "info.circle.fill"
        }
    }
}

/// What K*llTree keeps on disk: the closed vendors, so a Droppy relaunch keeps
/// guarding them and can still bring them back, and a short journal.
struct KillteeState: Codable, Sendable {
    var closed: [ClosedGroup] = []
    var journal: [JournalEntry] = []

    static let journalLimit = 40

    static func load(from url: URL) -> KillteeState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(KillteeState.self, from: data) else {
            return KillteeState()
        }
        return state
    }

    func save(to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
