//  Model for the Tidy tab.
//
//  CleanKind lists every cleanup card, with its title, plain-language blurb, icon, and safety
//  level. Safety decides what is pre-checked: .safe cards are, .review cards never are, .copies
//  and .mixed pre-check only the items the scanner marked. CleanupModel owns the scan results,
//  the selection state, and the two actions that change the disk: clean() (move to Trash with a
//  receipt) and emptyTrash() (via Finder). quietTidy() is the unattended weekly variant and only
//  touches CleanKind.quiet.

import Foundation
import AppKit
import Observation

// MARK: - Types

enum CleanKind: String, CaseIterable, Sendable, Identifiable, Codable {
    case caches, logs, installers, devCaches, claude, duplicates, leftovers, unusedApps, iosBackups, bigFiles
    var id: String { rawValue }

    var title: String {
        switch self {
        case .caches:     return String(localized: "App caches")
        case .logs:       return String(localized: "Old log files")
        case .installers: return String(localized: "Installers you've already used")
        case .devCaches:  return String(localized: "Developer tool caches")
        case .claude:     return String(localized: "Claude app")
        case .duplicates: return String(localized: "Exact duplicate files")
        case .leftovers:  return String(localized: "Leftovers from apps you removed")
        case .unusedApps: return String(localized: "Apps you haven't opened in a year")
        case .iosBackups: return String(localized: "Old iPhone and iPad backups")
        case .bigFiles:   return String(localized: "Your biggest files")
        }
    }

    var blurb: String {
        switch self {
        case .caches:     return String(localized: "Temporary files apps keep to load faster. They're rebuilt automatically, so clearing them is always safe.")
        case .logs:       return String(localized: "Diagnostic notes apps write for troubleshooting. Nothing you'll ever need.")
        case .installers: return String(localized: "Once an app is installed, the installer in Downloads isn't needed any more.")
        case .devCaches:  return String(localized: "Only shows up on Macs used for programming. The tools re-download whatever they need.")
        case .claude:     return String(localized: "Claude keeps rendering caches, old copies of Claude Code, a sandbox image, and every conversation transcript. Caches and old versions are checked; the sandbox and old transcripts are yours to decide.")
        case .duplicates: return String(localized: "Files that exist in more than one place with identical contents. The oldest copy is always kept. Extra copies in Downloads or on the Desktop are checked; copies inside your own folders are left for you to decide.")
        case .leftovers:  return String(localized: "Settings and support files from apps that are no longer on this Mac.")
        case .unusedApps: return String(localized: "Apps that haven't been opened in twelve months, according to Spotlight. Anything from the App Store can be downloaded again for free.")
        case .iosBackups: return String(localized: "Backups of iPhones and iPads stored on this Mac. If those devices back up to iCloud now, the old copies here may be safe to remove.")
        case .bigFiles:   return String(localized: "The largest single files in your home folder. Only you know if you still need them, so nothing here is pre-selected.")
        }
    }

    var icon: String {
        switch self {
        case .caches:     return "bolt.circle.fill"
        case .logs:       return "doc.text.fill"
        case .installers: return "shippingbox.fill"
        case .devCaches:  return "hammer.fill"
        case .claude:     return "bubble.left.and.text.bubble.right.fill"
        case .duplicates: return "doc.on.doc.fill"
        case .leftovers:  return "trash.slash.fill"
        case .unusedApps: return "app.dashed"
        case .iosBackups: return "iphone"
        case .bigFiles:   return "scalemass.fill"
        }
    }

    var safety: Safety {
        switch self {
        case .caches, .logs, .installers, .devCaches: return .safe
        case .duplicates: return .copies
        case .claude: return .mixed
        case .leftovers, .unusedApps, .iosBackups, .bigFiles: return .review
        }
    }

    var scanningLabel: String {
        switch self {
        case .caches:     return String(localized: "Checking app caches…")
        case .logs:       return String(localized: "Checking log files…")
        case .installers: return String(localized: "Looking for old installers…")
        case .devCaches:  return String(localized: "Checking developer caches…")
        case .claude:     return String(localized: "Checking what Claude left behind…")
        case .duplicates: return String(localized: "Looking for duplicate files (this one takes a moment)…")
        case .leftovers:  return String(localized: "Looking for leftovers from removed apps…")
        case .unusedApps: return String(localized: "Checking when each app was last opened…")
        case .iosBackups: return String(localized: "Checking for device backups…")
        case .bigFiles:   return String(localized: "Finding your biggest files…")
        }
    }

    /// The kinds a quiet, unattended tidy is allowed to touch.
    static let quiet: [CleanKind] = [.caches, .logs, .installers, .devCaches]   // .claude is deliberately excluded: its safe items depend on the app being closed
}

enum Safety: Sendable {
    case safe, copies, mixed, review
    var label: String {
        switch self {
        case .safe:   return String(localized: "Always safe")
        case .copies: return String(localized: "Keeps one copy")
        case .mixed:  return String(localized: "Safe parts checked")
        case .review: return String(localized: "Take a look first")
        }
    }
}

struct CleanItem: Identifiable, Sendable, Hashable {
    var id: String
    var paths: [String]
    var name: String
    var detail: String
    var size: Int64
    var selected: Bool
    var why: String = ""
    var protectedBy: String? = nil
    var keeperPath: String? = nil

    var isProtected: Bool { protectedBy != nil }
    var firstURL: URL? { paths.first.map { URL(fileURLWithPath: $0) } }
}

struct CleanCategory: Identifiable, Sendable {
    var kind: CleanKind
    var items: [CleanItem]
    var expanded: Bool = false

    var id: CleanKind { kind }
    var total: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedTotal: Int64 { items.filter(\.selected).reduce(0) { $0 + $1.size } }
    var selectedCount: Int { items.filter(\.selected).count }
    var selectable: [CleanItem] { items.filter { !$0.isProtected } }
    var allSelected: Bool { !selectable.isEmpty && selectable.allSatisfy(\.selected) }
}

struct DiskSpace: Sendable {
    var total: Int64
    var free: Int64
    var used: Int64 { max(0, total - free) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    static func current() -> DiskSpace? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = v.volumeTotalCapacity else { return nil }
        return DiskSpace(total: Int64(total), free: Int64(v.volumeAvailableCapacityForImportantUsage ?? 0))
    }
}

struct TrashState: Sendable {
    var size: Int64
    var count: Int
    var readable: Bool
}

// MARK: - Model

@MainActor
@Observable
final class CleanupModel {
    enum Phase: Equatable {
        case idle
        case scanning(String)
        case ready
        case cleaning(done: Int, total: Int)
        case finished(moved: Int, size: Int64, failed: Int)
        case emptyingTrash
        case trashEmptied(freed: Int64)
        case trashFailed(String)
    }

    var categories: [CleanCategory] = []
    var space: DiskSpace?
    var trash: TrashState?
    var phase: Phase = .idle
    var showConfirm = false
    var showTrashConfirm = false
    var quietTidyRunning = false

    var isScanning: Bool { if case .scanning = phase { return true } else { return false } }

    var selectedItems: [CleanItem] { categories.flatMap { $0.items.filter { $0.selected && !$0.isProtected } } }
    var selectedTotal: Int64 { selectedItems.reduce(0) { $0 + $1.size } }
    var selectedCount: Int { selectedItems.count }
    var lastTidy: Date? { History.shared.lastTidy }

    func scan() {
        guard !isScanning else { return }
        categories = []
        phase = .scanning(String(localized: "Looking around…"))
        Task {
            space = DiskSpace.current()
            trash = await Task.detached { Scanner.trashState() }.value
            // Duplicates last: it is the slow one, and the quick cards should not wait behind it.
            for kind in CleanKind.allCases.sorted(by: { ($0 == .duplicates ? 1 : 0) < ($1 == .duplicates ? 1 : 0) }) {
                phase = .scanning(kind.scanningLabel)
                let cat = await Task.detached(priority: .userInitiated) { Scanner.scan(kind) }.value
                if !cat.items.isEmpty { categories.append(cat) }
            }
            phase = .ready
        }
    }

    func setAll(_ kind: CleanKind, _ on: Bool) {
        guard let i = categories.firstIndex(where: { $0.kind == kind }) else { return }
        for j in categories[i].items.indices where !categories[i].items[j].isProtected {
            categories[i].items[j].selected = on
        }
    }

    func toggle(_ kind: CleanKind, _ itemID: String) {
        guard let i = categories.firstIndex(where: { $0.kind == kind }),
              let j = categories[i].items.firstIndex(where: { $0.id == itemID }),
              !categories[i].items[j].isProtected else { return }
        categories[i].items[j].selected.toggle()
    }

    func setExpanded(_ kind: CleanKind, _ on: Bool) {
        guard let i = categories.firstIndex(where: { $0.kind == kind }) else { return }
        categories[i].expanded = on
    }

    func setAllExpanded(_ on: Bool) {
        for i in categories.indices { categories[i].expanded = on }
    }

    /// Adds a path to the protected list and re-marks any items that match.
    func protect(_ path: String) {
        Protection.add(path)
        for i in categories.indices {
            for j in categories[i].items.indices where categories[i].items[j].paths.contains(where: { $0 == path || $0.hasPrefix(path + "/") }) {
                categories[i].items[j].protectedBy = String(localized: "on your protected list")
                categories[i].items[j].selected = false
            }
        }
    }

    /// Moves every selected item to the Trash and writes a receipt. Nothing is deleted outright.
    /// Items are processed one path at a time so the progress bar moves and a single refusal
    /// (macOS protects some container folders) doesn't abort the rest. Size is split evenly across
    /// an item's paths for the receipt; exact per-path sizes aren't worth a second enumeration.
    func clean() {
        let items = selectedItems
        guard !items.isEmpty else { return }
        let kindOf: [String: CleanKind] = Dictionary(uniqueKeysWithValues: categories.flatMap { c in c.items.map { ($0.id, c.kind) } })
        let total = items.reduce(0) { $0 + $1.paths.count }
        phase = .cleaning(done: 0, total: total)
        Task {
            var records: [TidyRecord] = []
            var done = 0
            for item in items {
                let per = item.size / Int64(max(item.paths.count, 1))
                for p in item.paths {
                    let trashPath = await Task.detached { Scanner.moveToTrash(p) }.value
                    records.append(TidyRecord(id: UUID(), name: item.name, originalPath: p, trashPath: trashPath,
                                              size: per, restored: false, kind: kindOf[item.id]))
                    done += 1
                    phase = .cleaning(done: done, total: total)
                }
            }
            let session = TidySession(id: UUID(), date: Date(), automatic: false, label: nil, records: records)
            History.shared.add(session)
            phase = .finished(moved: session.movedCount, size: session.totalSize, failed: session.failedCount)
            trash = await Task.detached { Scanner.trashState() }.value
        }
    }

    /// Unattended tidy of the always-safe categories only. Used by the weekly schedule and the menu bar.
    func quietTidy() async -> TidySession? {
        guard !quietTidyRunning, !isScanning else { return nil }
        quietTidyRunning = true
        defer { quietTidyRunning = false }
        var records: [TidyRecord] = []
        for kind in CleanKind.quiet {
            let cat = await Task.detached { Scanner.scan(kind) }.value
            for item in cat.items where item.selected && !item.isProtected {
                let per = item.size / Int64(max(item.paths.count, 1))
                for p in item.paths {
                    let trashPath = await Task.detached { Scanner.moveToTrash(p) }.value
                    records.append(TidyRecord(id: UUID(), name: item.name, originalPath: p, trashPath: trashPath,
                                              size: per, restored: false, kind: kind))
                }
            }
        }
        guard records.contains(where: \.moved) else { return nil }
        let session = TidySession(id: UUID(), date: Date(), automatic: true, label: String(localized: "Quiet tidy"), records: records)
        History.shared.add(session)
        space = DiskSpace.current()
        trash = await Task.detached { Scanner.trashState() }.value
        return session
    }

    func emptyTrash() {
        let before = trash?.size ?? 0
        phase = .emptyingTrash
        Task {
            let err = await Task.detached { Scanner.emptyTrash() }.value
            trash = await Task.detached { Scanner.trashState() }.value
            space = DiskSpace.current()
            if let err { phase = .trashFailed(err) } else { phase = .trashEmptied(freed: before) }
        }
    }

    func finishAndRescan() {
        showConfirm = false
        showTrashConfirm = false
        phase = .idle
        scan()
    }
}

// MARK: - Friendly formatting

extension Bytes {
    /// "about 1,200 photos' worth" — a size people can picture.
    static func friendly(_ n: Int64) -> String {
        let photo: Int64 = 3_000_000
        let song: Int64 = 8_000_000
        let movieHour: Int64 = 2_000_000_000
        if n >= movieHour * 2 {
            let hrs = Int(Double(n) / Double(movieHour))
            return String(localized: "about \(hrs) hours of HD video")
        }
        if n >= song * 20 { return String(localized: "about \(Int(n / song)) songs' worth") }
        if n >= photo * 5 { return String(localized: "about \(Int(n / photo)) photos' worth") }
        return String(localized: "a little bit of space")
    }
}
