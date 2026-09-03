//  Exact-duplicate detection: bucket by size, then SHA-256 the candidates.
//
//  Deliberately conservative after a real incident: files inside git checkouts and dependency
//  folders are skipped (projects repeat assets on purpose), and only extra copies living in
//  Downloads or on the Desktop are pre-checked, since that's where accidental re-downloads land.
//  The oldest copy is always the one kept.
//
//  Cloud placeholders are never opened. With Desktop & Documents in iCloud most files are
//  "dataless" until read, and reading one makes iCloud download it; a scan that did that filled a
//  Mac's disk until macOS started pausing apps. The scan also hashes the first 128 KB before the
//  whole file, and stops after a time and byte budget so it can never run for hours.

import Foundation
import CryptoKit

/// Finds files with byte-for-byte identical contents in the home folder.
enum Duplicates {
    static let timeBudget: TimeInterval = 90
    static let byteBudget: Int64 = 6_000_000_000
    /// Set by the last scan when it hit a budget, so the card can say the list may be incomplete.
    nonisolated(unsafe) static var lastScanWasCutShort = false

    /// True for files whose bytes are not on this disk (iCloud, Dropbox, OneDrive, Google Drive placeholders).
    static func isDataless(_ url: URL) -> Bool {
        var st = stat()
        if lstat(url.path, &st) == 0, st.st_flags & UInt32(SF_DATALESS) != 0 { return true }
        if let v = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
           v.isUbiquitousItem == true, let status = v.ubiquitousItemDownloadingStatus, status != .current { return true }
        return false
    }

    static func scan() -> [CleanItem] {
        let started = Date()
        var hashedBytes: Int64 = 0
        lastScanWasCutShort = false
        func overBudget() -> Bool {
            if Date().timeIntervalSince(started) > timeBudget || hashedBytes > byteBudget { lastScanWasCutShort = true; return true }
            return false
        }
        let home = Scanner.home
        let libraryPath = Scanner.library.path
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .isPackageKey]
        guard let e = FileManager.default.enumerator(at: home, includingPropertiesForKeys: keys,
                                                     options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                                     errorHandler: { _, _ in true }) else { return [] }

        // Pass 1: bucket by size. Only same-size files can be duplicates.
        var bySize: [Int: [(URL, Date?)]] = [:]
        var repoCache: [String: Bool] = [:]
        /// Source-code checkouts and dependency folders repeat files on purpose. Leave them alone.
        func isManaged(_ url: URL) -> Bool {
            let dir = url.deletingLastPathComponent().path
            if dir.contains("/node_modules/") || dir.hasSuffix("/node_modules") || dir.contains("/.venv/") || dir.contains("/Pods/") { return true }
            if let c = repoCache[dir] { return c }
            var cur = dir
            var found = false
            while cur.count > home.path.count {
                if let c = repoCache[cur] { found = c; break }
                if FileManager.default.fileExists(atPath: cur + "/.git") { found = true; break }
                cur = (cur as NSString).deletingLastPathComponent
            }
            repoCache[dir] = found
            return found
        }
        for case let f as URL in e {
            if f.path.hasPrefix(libraryPath) { e.skipDescendants(); continue }
            guard let v = try? f.resourceValues(forKeys: Set(keys)) else { continue }
            if v.isPackage == true { e.skipDescendants(); continue }
            if v.isRegularFile == true, isManaged(f) { continue }
            guard v.isRegularFile == true, let s = v.fileSize, s >= 1_000_000, s <= 4_000_000_000 else { continue }
            if isDataless(f) { continue }
            bySize[s, default: []].append((f, v.contentModificationDate))
            if overBudget() { break }
        }

        // Pass 2: hash the first 128 KB of each candidate; only files whose prefixes agree get a full hash.
        var groups: [(size: Int, files: [(URL, Date?)])] = []
        outer: for (size, files) in bySize.sorted(by: { $0.key > $1.key }) where files.count > 1 {
            var byPrefix: [String: [(URL, Date?)]] = [:]
            for f in files {
                if overBudget() { break outer }
                if let h = sha256(f.0, limit: 131_072) { byPrefix[h, default: []].append(f); hashedBytes += 131_072 }
            }
            for (_, candidates) in byPrefix where candidates.count > 1 {
                var byHash: [String: [(URL, Date?)]] = [:]
                for f in candidates {
                    if overBudget() { break outer }
                    if let h = sha256(f.0) { byHash[h, default: []].append(f); hashedBytes += Int64(size) }
                }
                for (_, g) in byHash where g.count > 1 { groups.append((size, g)) }
            }
        }

        return groups.map { size, g in
            let sorted = g.sorted { ($0.1 ?? .distantPast) < ($1.1 ?? .distantPast) }
            let keeper = sorted[0].0
            let extras = sorted.dropFirst().map(\.0)
            let protectedBy = ([keeper] + extras).compactMap { Protection.reason(for: $0.path) }.first
            let keeperFolder = Scanner.friendlyFolder(keeper)
            // Only pre-check copies sitting in Downloads or on the Desktop: that's where accidental re-downloads land.
            // Copies elsewhere may be deliberate (a project that reuses an asset), so they're shown unchecked.
            let casual = [home.appendingPathComponent("Downloads").path + "/", home.appendingPathComponent("Desktop").path + "/"]
            let preCheck = protectedBy == nil && extras.allSatisfy { u in casual.contains { u.path.hasPrefix($0) } }
            return CleanItem(
                id: "dup:" + keeper.path,
                paths: extras.map(\.path),
                name: keeper.lastPathComponent,
                detail: String(localized: "\(g.count) identical copies · keeping the one in \(keeperFolder)"),
                size: Int64(size) * Int64(extras.count),
                selected: preCheck,
                why: String(localized: "These files have exactly the same contents, byte for byte. One copy is enough. The oldest copy, in \(keeperFolder), is kept. Copies in Downloads or on the Desktop are checked for you; copies inside your own folders are left for you to decide, since a project may use the same file in several places."),
                protectedBy: protectedBy,
                keeperPath: keeper.path)
        }
    }

    /// SHA-256 of the file, or of its first `limit` bytes.
    static func sha256(_ url: URL, limit: Int = .max) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        var remaining = limit
        while remaining > 0, let chunk = try? h.read(upToCount: min(4_000_000, remaining)), !chunk.isEmpty {
            hasher.update(data: chunk)
            remaining -= chunk.count
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
