//  Receipts. Every session that moves anything (Tidy Up, quiet tidy, uninstall, agent disable)
//  records each path with where it landed in the Trash, persisted as JSON under
//  ~/Library/Application Support/Tidy Mac/history.json. restore() moves a record back to its
//  original path, which works until the Trash is emptied.

import Foundation
import Observation

/// One file (or folder) Tidy for Mac moved to the Trash.
struct TidyRecord: Codable, Identifiable, Sendable, Hashable {
    var id: UUID
    var name: String
    var originalPath: String
    var trashPath: String?        // nil means the move failed
    var size: Int64
    var restored: Bool
    var kind: CleanKind?

    var moved: Bool { trashPath != nil }
}

/// One tidy session: a click of Tidy Up, a quiet weekly tidy, or an uninstall.
struct TidySession: Codable, Identifiable, Sendable, Hashable {
    var id: UUID
    var date: Date
    var automatic: Bool
    var label: String?
    var records: [TidyRecord]

    var movedCount: Int { records.filter(\.moved).count }
    var failedCount: Int { records.filter { !$0.moved }.count }
    var totalSize: Int64 { records.filter(\.moved).reduce(0) { $0 + $1.size } }
    var restorableCount: Int { records.filter { $0.moved && !$0.restored }.count }
}

enum RestoreOutcome: Sendable {
    case restored
    case gone          // the Trash was emptied
    case alreadyExists // something else now lives at the original path
    case failed(String)
}

/// Persistent receipt of everything Tidy for Mac has ever done, so any of it can be put back.
@MainActor
@Observable
final class History {
    static let shared = History()

    var sessions: [TidySession] = []

    private static let dir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Tidy Mac", isDirectory: true)
    }()
    private static let file = dir.appendingPathComponent("history.json")

    init() {
        if let data = try? Data(contentsOf: Self.file),
           let s = try? JSONDecoder().decode([TidySession].self, from: data) {
            sessions = s.sorted { $0.date > $1.date }
        }
    }

    var lastTidy: Date? { sessions.first?.date }

    func add(_ session: TidySession) {
        sessions.insert(session, at: 0)
        save()
    }

    private func save() {
        try? FileManager.default.createDirectory(at: Self.dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(sessions) {
            try? data.write(to: Self.file, options: .atomic)
        }
    }

    /// Moves a record back out of the Trash to where it came from.
    func restore(_ record: TidyRecord, in session: TidySession) async -> RestoreOutcome {
        let outcome = await Task.detached { Self.restoreOnDisk(record) }.value
        if case .restored = outcome,
           let si = sessions.firstIndex(where: { $0.id == session.id }),
           let ri = sessions[si].records.firstIndex(where: { $0.id == record.id }) {
            sessions[si].records[ri].restored = true
            save()
        }
        return outcome
    }

    func restoreAll(in session: TidySession) async -> (restored: Int, gone: Int, failed: Int) {
        var r = 0, g = 0, f = 0
        for rec in session.records where rec.moved && !rec.restored {
            switch await restore(rec, in: session) {
            case .restored: r += 1
            case .gone: g += 1
            default: f += 1
            }
        }
        return (r, g, f)
    }

    /// Three ways a restore can fail, each reported differently to the user: the Trash was emptied
    /// (gone), something new now occupies the original path (alreadyExists; never overwrite), or
    /// the move itself failed (permissions, missing volume).
    /// Synchronous variant for the command line, which has no run loop to await on.
    func restoreAllSync(in session: TidySession) -> (restored: Int, gone: Int, failed: Int) {
        var r = 0, g = 0, f = 0
        guard let si = sessions.firstIndex(where: { $0.id == session.id }) else { return (0, 0, 0) }
        for ri in sessions[si].records.indices where sessions[si].records[ri].moved && !sessions[si].records[ri].restored {
            switch Self.restoreOnDisk(sessions[si].records[ri]) {
            case .restored: sessions[si].records[ri].restored = true; r += 1
            case .gone: g += 1
            default: f += 1
            }
        }
        save()
        return (r, g, f)
    }

    nonisolated private static func restoreOnDisk(_ r: TidyRecord) -> RestoreOutcome {
        let fm = FileManager.default
        guard let t = r.trashPath, fm.fileExists(atPath: t) else { return .gone }
        if fm.fileExists(atPath: r.originalPath) { return .alreadyExists }
        do {
            let parent = (r.originalPath as NSString).deletingLastPathComponent
            try fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
            try fm.moveItem(atPath: t, toPath: r.originalPath)
            return .restored
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
