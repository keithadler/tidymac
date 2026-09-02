//  File-system scanning for the Tidy tab. Everything here is a pure function that runs off the
//  main thread and returns Sendable values; the model decides what to do with them.
//
//  Two rules shape this file:
//  - Nothing is ever deleted. moveToTrash() is the only write, and it goes through
//    FileManager.trashItem so the Trash keeps the original.
//  - Every CleanItem carries a `why` string, because a checkbox the user can't explain is a
//    checkbox they won't trust.

import Foundation
import AppKit

/// All the file-system work. Runs off the main thread; returns plain values.
enum Scanner {

    static let fm = FileManager.default
    static let home = URL(fileURLWithPath: NSHomeDirectory())
    static var library: URL { home.appendingPathComponent("Library") }

    // MARK: Entry point

    static func scan(_ kind: CleanKind) -> CleanCategory {
        var items: [CleanItem]
        switch kind {
        case .caches:     items = scanCaches()
        case .logs:       items = scanLogs()
        case .installers: items = scanInstallers()
        case .devCaches:  items = scanDevCaches()
        case .claude:     items = scanClaude()
        case .duplicates: items = Duplicates.scan()
        case .leftovers:  items = scanLeftovers()
        case .unusedApps: items = scanUnusedApps()
        case .iosBackups: items = scanIOSBackups()
        case .bigFiles:   items = scanBigFiles()
        }
        // Protected items stay visible, with a shield, but can never be selected.
        for i in items.indices where items[i].protectedBy == nil {
            if let why = items[i].paths.compactMap({ Protection.reason(for: $0, allowBackups: kind == .iosBackups) }).first {
                items[i].protectedBy = why
                items[i].selected = false
            }
        }
        return CleanCategory(kind: kind, items: items.sorted { $0.size > $1.size })
    }

    // MARK: Helpers

    static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey, .isDirectoryKey]
        if let v = try? url.resourceValues(forKeys: keys), v.isDirectory != true {
            return Int64(v.totalFileAllocatedSize ?? 0)
        }
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in e {
            if let v = try? f.resourceValues(forKeys: keys), v.isRegularFile == true {
                total += Int64(v.totalFileAllocatedSize ?? 0)
            }
        }
        return total
    }

    static func modified(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    static func contents(_ url: URL) -> [URL] {
        (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey], options: [])) ?? []
    }

    static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
    }()

    static func ago(_ d: Date?) -> String {
        guard let d else { return "" }
        let days = Int(Date().timeIntervalSince(d) / 86400)
        if days < 1 { return String(localized: "used today") }
        if days < 30 { return String(localized: "used \(days) days ago") }
        if days < 365 { return String(localized: "last used \(days / 30) months ago") }
        return String(localized: "last used \(dateFmt.string(from: d))")
    }

    /// "Downloads" or "Documents/Taxes", relative to home.
    static func friendlyFolder(_ url: URL) -> String {
        let rel = url.deletingLastPathComponent().path.replacingOccurrences(of: home.path, with: "")
        let trimmed = rel.hasPrefix("/") ? String(rel.dropFirst()) : rel
        return trimmed.isEmpty ? String(localized: "your home folder") : trimmed
    }

    static func looksLikeBundleID(_ s: String) -> Bool {
        s.split(separator: ".").count >= 2 &&
        s.range(of: #"^[A-Za-z0-9\-]+(\.[A-Za-z0-9_\-]+)+$"#, options: .regularExpression) != nil
    }

    static func isApple(_ s: String) -> Bool {
        let l = s.lowercased()
        return l.hasPrefix("com.apple") || l.hasPrefix("group.com.apple") || l.hasPrefix("systemgroup.com.apple") || l.contains("apple.")
    }

    /// Human name for a bundle id: the installed app's name if there is one, else "Vendor · Product".
    static func friendlyName(bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url.deletingPathExtension().lastPathComponent
        }
        let parts = bundleID.split(separator: ".").map(String.init)
        guard parts.count >= 3 else { return bundleID }
        func cap(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }
        let rest = parts.dropFirst(2).map { cap($0.replacingOccurrences(of: "-", with: " ")) }.joined(separator: " ")
        return "\(cap(parts[1])) · \(rest)"
    }

    static func displayName(_ folder: String) -> String {
        looksLikeBundleID(folder) && folder.split(separator: ".").count >= 3 ? friendlyName(bundleID: folder) : folder
    }

    static var runningBundleIDs: Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    // MARK: Installed apps (for leftover detection)

    struct Installed {
        var ids = Set<String>()
        var vendors = Set<String>()
        var names: [String] = []
    }

    static func installedApps() -> Installed {
        var inst = Installed()
        let dirs = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                    "/System/Library/CoreServices", home.appendingPathComponent("Applications").path]
        for d in dirs {
            for u in contents(URL(fileURLWithPath: d)) where u.pathExtension == "app" {
                inst.names.append(u.deletingPathExtension().lastPathComponent.lowercased())
                if let id = Bundle(url: u)?.bundleIdentifier { inst.ids.insert(id) }
            }
        }
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier { inst.ids.insert(id) }
            if let n = app.localizedName { inst.names.append(n.lowercased()) }
        }
        for id in inst.ids {
            let p = id.split(separator: ".")
            if p.count >= 2 { inst.vendors.insert(p.prefix(2).joined(separator: ".").lowercased()) }
        }
        return inst
    }

    /// Decides whether a bundle id belongs to an app that is no longer installed. Every test here
    /// errs toward "still installed", because a false positive lands someone's live settings in the
    /// leftovers card:
    ///   1. Apple ids are never leftovers.
    ///   2. Anything found in /Applications & co, or currently running, is installed.
    ///   3. LaunchServices may know an app we didn't enumerate (odd install locations).
    ///   4. Two-part ids ("com.foo") are too ambiguous to judge.
    ///   5. If any installed app shares the vendor prefix ("com.adobe"), assume a helper of a
    ///      live product rather than a leftover.
    static func isOrphan(_ bundleID: String, _ inst: Installed) -> Bool {
        if isApple(bundleID) { return false }
        if inst.ids.contains(bundleID) { return false }
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil { return false }
        let p = bundleID.split(separator: ".")
        guard p.count >= 3 else { return false }   // two-part ids are too ambiguous to judge
        if inst.vendors.contains(p.prefix(2).joined(separator: ".").lowercased()) { return false }
        return true
    }

    // MARK: Categories

    static func scanCaches() -> [CleanItem] {
        var out: [CleanItem] = []
        // Caches for apps that are open right now are listed but left unchecked: yanking a cache from
        // under a running app is usually harmless but occasionally confuses it, and the gain is small.
        let running = runningBundleIDs
        let runningNames = Set(NSWorkspace.shared.runningApplications.compactMap { $0.localizedName?.lowercased() })
        for u in contents(library.appendingPathComponent("Caches")) {
            let n = u.lastPathComponent
            if isApple(n) || n == "CloudKit" || n.hasPrefix(".") { continue }
            let sz = size(of: u)
            if sz < 1_000_000 { continue }
            let name = displayName(n)
            let open = running.contains(n) || runningNames.contains(where: { $0 == n.lowercased() || $0 == name.lowercased() })
            out.append(CleanItem(
                id: u.path, paths: [u.path], name: name,
                detail: open ? String(localized: "Cache · that app is open right now, so it's left unchecked") : "Cache · \(ago(modified(u)))",
                size: sz, selected: !open,
                why: String(localized: "\(name) keeps temporary copies of things it downloads or works out, so it opens faster next time. If this folder is removed the app simply makes a fresh one. Nothing you made is stored here.")))
        }
        return out
    }

    static func scanLogs() -> [CleanItem] {
        var out: [CleanItem] = []
        for u in contents(library.appendingPathComponent("Logs")) where !u.lastPathComponent.hasPrefix(".") {
            let sz = size(of: u)
            if sz < 200_000 { continue }
            let name = displayName(u.lastPathComponent)
            out.append(CleanItem(
                id: u.path, paths: [u.path], name: name, detail: "Logs · \(ago(modified(u)))", size: sz, selected: true,
                why: String(localized: "Apps write notes about what they did in case a technician ever needs to troubleshoot. \(name) never reads these itself, and they grow forever if nobody clears them.")))
        }
        return out
    }

    static func scanInstallers() -> [CleanItem] {
        var out: [CleanItem] = []
        let exts: Set<String> = ["dmg", "pkg", "mpkg", "iso", "xip"]
        for u in contents(home.appendingPathComponent("Downloads")) where exts.contains(u.pathExtension.lowercased()) {
            let m = modified(u)
            let days = m.map { Int(Date().timeIntervalSince($0) / 86400) } ?? 0
            out.append(CleanItem(
                id: u.path, paths: [u.path], name: u.lastPathComponent,
                detail: String(localized: "Downloaded \(m.map(dateFmt.string(from:)) ?? "a while ago")"),
                size: size(of: u), selected: days >= 14,
                why: String(localized: "This is the package you downloaded to install an app. Once the app is in your Applications folder, the installer is just a copy of the download and can be fetched again from the maker's website if it's ever needed.")))
        }
        return out
    }

    static func scanDevCaches() -> [CleanItem] {
        let candidates: [(String, String)] = [
            (".npm/_cacache", "npm package cache"), (".npm/_npx", "npx package cache"),
            (".cache/pip", "pip package cache"), (".cache/uv", "uv package cache"),
            (".gradle/caches", "Gradle cache"), (".cocoapods/repos", "CocoaPods specs"),
            ("Library/Developer/Xcode/DerivedData", "Xcode build products"),
            ("Library/Developer/CoreSimulator/Caches", "iOS Simulator cache"),
        ]
        var out: [CleanItem] = []
        for (rel, label) in candidates {
            let u = home.appendingPathComponent(rel)
            guard fm.fileExists(atPath: u.path) else { continue }
            let sz = size(of: u)
            if sz < 1_000_000 { continue }
            out.append(CleanItem(
                id: u.path, paths: [u.path], name: label, detail: "~/\(rel)", size: sz, selected: true,
                why: String(localized: "Programming tools keep downloaded packages and build output here so the next build is quicker. They re-download or rebuild anything they need, so this is safe to clear at any time.")))
        }
        return out
    }

    /// The Claude desktop app and Claude Code: caches, superseded versions, sandbox image, old transcripts.
    static func scanClaude() -> [CleanItem] {
        var out: [CleanItem] = []
        let base = library.appendingPathComponent("Application Support/Claude")
        guard fm.fileExists(atPath: base.path) else { return [] }
        let open = runningBundleIDs.contains("com.anthropic.claudefordesktop")

        for name in ["Cache", "Code Cache", "GPUCache", "DawnWebGPUCache", "DawnGraphiteCache"] {
            let u = base.appendingPathComponent(name)
            guard fm.fileExists(atPath: u.path) else { continue }
            let sz = size(of: u)
            if sz < 1_000_000 { continue }
            out.append(CleanItem(
                id: u.path, paths: [u.path], name: String(localized: "Claude rendering cache · \(name)"),
                detail: open ? String(localized: "Claude is open right now, so it's left unchecked") : "\(ago(modified(u)))",
                size: sz, selected: !open,
                why: String(localized: "Claude is built on a web engine and caches images, scripts, and fonts here so windows open quickly. It rebuilds this automatically. Best cleared while Claude is closed.")))
        }

        // Claude Code ships inside the app, one folder per version; only the newest is used.
        let versions = contents(base.appendingPathComponent("claude-code")).filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        for v in versions.dropLast() {
            out.append(CleanItem(
                id: v.path, paths: [v.path], name: String(localized: "Old Claude Code version \(v.lastPathComponent)"),
                detail: String(localized: "superseded by \(versions.last!.lastPathComponent)"), size: size(of: v), selected: true,
                why: String(localized: "Claude updates Claude Code by adding a new version folder next to the old one. Only the newest, \(versions.last!.lastPathComponent), is used. Older folders are never opened again.")))
        }

        let vm = base.appendingPathComponent("vm_bundles")
        if fm.fileExists(atPath: vm.path) {
            let sz = size(of: vm)
            if sz > 50_000_000 {
                out.append(CleanItem(
                    id: vm.path, paths: [vm.path], name: String(localized: "Claude sandbox image"),
                    detail: String(localized: "used for isolated sessions · \(ago(modified(vm)))"), size: sz, selected: false,
                    why: String(localized: "A small virtual machine Claude uses to run tasks in isolation. If you remove it, Claude downloads a fresh one, about \(Bytes.string(sz)), the next time it needs one. Leave it if you use those features regularly.")))
            }
        }
        let vm2 = base.appendingPathComponent("claude-code-vm")
        if fm.fileExists(atPath: vm2.path) {
            let sz = size(of: vm2)
            if sz > 20_000_000 {
                out.append(CleanItem(
                    id: vm2.path, paths: [vm2.path], name: String(localized: "Claude Code sandbox files"),
                    detail: "\(ago(modified(vm2)))", size: sz, selected: false,
                    why: String(localized: "Support files for Claude Code's sandboxed mode. Re-created on demand if removed.")))
            }
        }

        // Old conversation transcripts under ~/.claude/projects
        let cutoff = Date().addingTimeInterval(-30 * 86400)
        let projects = home.appendingPathComponent(".claude/projects")
        if let e = fm.enumerator(at: projects, includingPropertiesForKeys: [.contentModificationDateKey, .totalFileAllocatedSizeKey, .isRegularFileKey], options: [], errorHandler: { _, _ in true }) {
            var paths: [String] = []
            var total: Int64 = 0
            for case let f as URL in e where f.pathExtension == "jsonl" {
                guard let v = try? f.resourceValues(forKeys: [.contentModificationDateKey, .totalFileAllocatedSizeKey, .isRegularFileKey]),
                      v.isRegularFile == true, let m = v.contentModificationDate, m < cutoff else { continue }
                paths.append(f.path)
                total += Int64(v.totalFileAllocatedSize ?? 0)
            }
            if !paths.isEmpty {
                out.append(CleanItem(
                    id: "claude-transcripts", paths: paths, name: String(localized: "Claude Code conversations older than a month"),
                    detail: String(localized: "\(paths.count) transcripts"), size: total, selected: false,
                    why: String(localized: "Claude Code keeps a transcript of every session so you can resume it later. Ones untouched for a month are rarely resumed, but they are your history, so they are not pre-checked.")))
            }
        }
        return out
    }

    static func scanLeftovers() -> [CleanItem] {
        let inst = installedApps()
        let cutoff = Date().addingTimeInterval(-30 * 86400)
        var groups: [String: (paths: [String], size: Int64, newest: Date?, kinds: Set<String>)] = [:]

        func add(_ key: String, _ u: URL, _ kind: String) {
            var g = groups[key] ?? ([], 0, nil, [])
            g.paths.append(u.path); g.size += size(of: u); g.kinds.insert(kind)
            if let m = modified(u), g.newest == nil || m > g.newest! { g.newest = m }
            groups[key] = g
        }

        let places: [(String, String, (String) -> String?)] = [
            ("Application Support", String(localized: "support files"), { $0 }),
            ("Containers", String(localized: "app container"), { $0 }),
            ("Saved Application State", String(localized: "window state"), { $0.hasSuffix(".savedState") ? String($0.dropLast(11)) : nil }),
            ("HTTPStorages", String(localized: "web data"), { $0.hasSuffix(".binarycookies") ? String($0.dropLast(14)) : $0 }),
            ("WebKit", String(localized: "web data"), { $0 }),
            ("Preferences", String(localized: "settings"), { $0.hasSuffix(".plist") ? String($0.dropLast(6)) : nil }),
        ]
        for (dir, kind, extract) in places {
            for u in contents(library.appendingPathComponent(dir)) {
                guard let id = extract(u.lastPathComponent), looksLikeBundleID(id), isOrphan(id, inst) else { continue }
                if let m = modified(u), m > cutoff { continue }
                add(id, u, kind)
            }
        }

        // Application Support folders with plain names (e.g. "Kiro") have no bundle id to look up, so they
        // are only flagged when: not on this system-folder skip list, no installed app name contains the
        // folder name (or vice versa), no installed vendor prefix ends with it, untouched for 30 days, and
        // over 5 MB. They still land in a "take a look first" card, unchecked.
        let skip: Set<String> = ["addressbook", "callhistorydb", "callhistorytransactions", "clouddocs", "crashreporter", "caches",
                                 "dock", "icloud", "knowledge", "mobilesync", "mail", "photos", "syncservices", "fileprovider",
                                 "app store", "apple", "script editor", "imovie", "garageband", "logic", "audio", "adobe",
                                 "microsoft", "google", "mozilla", "firefox", "dropbox", "steam", "code", "jetbrains",
                                 "ilifemediabrowser", "keychain", "spotlight", "quick look", "sharedfilelist", "icdd", "networkextension", "tidy mac"]
        for u in contents(library.appendingPathComponent("Application Support")) {
            let n = u.lastPathComponent
            if n.hasPrefix(".") || looksLikeBundleID(n) || isApple(n) || skip.contains(n.lowercased()) { continue }
            let l = n.lowercased()
            if inst.names.contains(where: { $0.contains(l) || l.contains($0) }) { continue }
            if inst.vendors.contains(where: { $0.hasSuffix(".\(l)") }) { continue }
            if let m = modified(u), m > cutoff { continue }
            let sz = size(of: u)
            if sz < 5_000_000 { continue }
            add("name:" + n, u, String(localized: "support files"))
        }

        return groups.map { key, g in
            let name = key.hasPrefix("name:") ? String(key.dropFirst(5)) : friendlyName(bundleID: key)
            let what = g.kinds.sorted().joined(separator: ", ")
            return CleanItem(
                id: key, paths: g.paths, name: name, detail: "\(what) · \(ago(g.newest))", size: g.size, selected: false,
                why: String(localized: "This belongs to \(name), which isn't installed on this Mac any more. Apps leave settings and support data behind when they're dragged to the Trash. If you reinstall \(name) later it will start fresh, which is usually fine."))
        }
    }

    /// Spotlight's last-opened date for a file, or nil when it has none ("never opened, as far as Spotlight knows").
    static func lastUsed(_ u: URL) -> Date? {
        guard Capabilities.mdls else { return nil }
        let raw = SystemInfo.run("/usr/bin/mdls", ["-name", "kMDItemLastUsedDate", "-raw", u.path], timeout: 10).trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw != "(null)", !raw.isEmpty else { return nil }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }

    /// Apps not opened in a year, by Spotlight's last-used date. Never pre-checked.
    static func scanUnusedApps() -> [CleanItem] {
        guard Capabilities.mdls else { return [] }   // no Spotlight metadata tool, no "last opened" dates: hide the card
        var out: [CleanItem] = []
        let cutoff = Date().addingTimeInterval(-365 * 86400)
        let running = runningBundleIDs
        for u in contents(URL(fileURLWithPath: "/Applications")) where u.pathExtension == "app" {
            guard let bid = Bundle(url: u)?.bundleIdentifier, !bid.hasPrefix("com.apple."), !running.contains(bid),
                  bid != Bundle.main.bundleIdentifier else { continue }
            let last = lastUsed(u)
            let added = (try? u.resourceValues(forKeys: [.addedToDirectoryDateKey]))?.addedToDirectoryDate ?? modified(u)
            // Never opened but installed recently: give it time.
            if last == nil, let a = added, a > cutoff { continue }
            if let l = last, l > cutoff { continue }
            let name = u.deletingPathExtension().lastPathComponent
            let sz = size(of: u)
            let when = last.map { String(localized: "last opened \(dateFmt.string(from: $0))") } ?? String(localized: "never opened, as far as Spotlight can tell")
            let store = fm.fileExists(atPath: u.appendingPathComponent("Contents/_MASReceipt/receipt").path)
            out.append(CleanItem(
                id: u.path, paths: [u.path], name: name, detail: "\(when)\(store ? " · App Store" : "")", size: sz, selected: false,
                why: String(localized: "\(name) hasn't been opened in over a year. Removing it frees \(Bytes.string(sz)).\(store ? " It came from the App Store, so it can be downloaded again any time at no cost." : " You'd need the installer or the maker's website to get it back.") Its settings and support files will show up under Leftovers on the next scan.")))
        }
        return out
    }

    static func scanIOSBackups() -> [CleanItem] {
        var out: [CleanItem] = []
        for u in contents(library.appendingPathComponent("Application Support/MobileSync/Backup")) {
            let info = NSDictionary(contentsOf: u.appendingPathComponent("Info.plist")) as? [String: Any]
            let device = info?["Device Name"] as? String ?? String(localized: "Unknown device")
            let product = info?["Product Name"] as? String ?? ""
            let date = info?["Last Backup Date"] as? Date
            let when = date.map(dateFmt.string(from:)) ?? String(localized: "an unknown date")
            out.append(CleanItem(
                id: u.path, paths: [u.path], name: device,
                detail: "\(product)\(product.isEmpty ? "" : " · ")\(String(localized: "backed up \(when)"))",
                size: size(of: u), selected: false,
                why: String(localized: "A full backup of \(device) made by Finder or iTunes on \(when). If that device now backs up to iCloud, or you no longer have it, this copy isn't needed. If it's the only backup of a device you still use, keep it.")))
        }
        return out
    }

    static func scanBigFiles() -> [CleanItem] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .contentModificationDateKey, .isPackageKey]
        guard let e = fm.enumerator(at: home, includingPropertiesForKeys: keys,
                                    options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in true }) else { return [] }
        let libraryPath = library.path
        var found: [(URL, Int64, Date?)] = []
        for case let f as URL in e {
            if f.path.hasPrefix(libraryPath) { e.skipDescendants(); continue }
            guard let v = try? f.resourceValues(forKeys: Set(keys)) else { continue }
            if v.isPackage == true { e.skipDescendants(); continue }
            guard v.isRegularFile == true, let s = v.totalFileAllocatedSize, s >= 500_000_000 else { continue }
            found.append((f, Int64(s), v.contentModificationDate))
        }
        return found.sorted { $0.1 > $1.1 }.prefix(25).map { f, s, d in
            CleanItem(
                id: f.path, paths: [f.path], name: f.lastPathComponent,
                detail: String(localized: "in \(friendlyFolder(f)) · \(ago(d))"), size: s, selected: false,
                why: String(localized: "This is one of the largest files in your home folder. Tidy for Mac can't know whether it matters to you, so it's only listed here to help you decide. Use the magnifying glass to see it in Finder first."))
        }
    }

    // MARK: Uninstaller support

    /// Everything on disk that belongs to an app: support files, caches, settings, containers, login items.
    static func relatedFiles(appPath: String, bundleID: String?, appName: String) -> [CleanItem] {
        var out: [CleanItem] = []
        let bid = bundleID?.lowercased()
        let name = appName.lowercased()
        let nameUsable = name.count >= 4

        func matches(_ entry: String, exactNameOK: Bool) -> Bool {
            let e = entry.lowercased()
            if let bid {
                if e == bid || e.hasPrefix(bid + ".") || e == bid + ".plist" || e == bid + ".savedstate" || e == bid + ".binarycookies" { return true }
                if e.hasSuffix("." + bid) { return true }   // TEAMID.bundle.id group containers
            }
            if exactNameOK && nameUsable && (e == name || e == name + ".plist") { return true }
            return false
        }

        let places: [(String, String, Bool)] = [
            ("Application Support", String(localized: "support files"), true),
            ("Caches", String(localized: "cache"), true),
            ("Preferences", String(localized: "settings"), false),
            ("Containers", String(localized: "app container"), false),
            ("Group Containers", String(localized: "shared container"), false),
            ("Saved Application State", String(localized: "window state"), false),
            ("HTTPStorages", String(localized: "web data"), false),
            ("WebKit", String(localized: "web data"), false),
            ("Logs", String(localized: "logs"), true),
            ("LaunchAgents", String(localized: "background helper"), false),
            ("Application Scripts", String(localized: "scripts"), false),
        ]
        for (dir, kind, nameOK) in places {
            for u in contents(library.appendingPathComponent(dir)) where matches(u.lastPathComponent, exactNameOK: nameOK) {
                let sz = size(of: u)
                out.append(CleanItem(
                    id: u.path, paths: [u.path], name: "\(kind) · \(u.lastPathComponent)", detail: "~/Library/\(dir)",
                    size: sz, selected: true,
                    why: String(localized: "Created by \(appName). Once the app is gone this has no use, and removing it lets a future reinstall start clean.")))
            }
        }
        return out.sorted { $0.size > $1.size }
    }

    // MARK: Trash

    static func trashState() -> TrashState {
        let t = home.appendingPathComponent(".Trash")
        guard let items = try? fm.contentsOfDirectory(at: t, includingPropertiesForKeys: nil, options: []) else {
            return TrashState(size: 0, count: 0, readable: false)
        }
        return TrashState(size: items.reduce(0) { $0 + size(of: $1) }, count: items.count, readable: true)
    }

    /// Moves a path to the Trash. Returns where it landed (the Trash may rename on collision), or nil
    /// if macOS refused. The returned path is what the receipt uses to put the item back later.
    /// This is the only function in the app that changes user files.
    static func moveToTrash(_ path: String) -> String? {
        var result: NSURL?
        do {
            try fm.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &result)
            return result?.path
        } catch {
            return nil
        }
    }

    /// Asks Finder to empty the Trash. Returns an error message, or nil on success.
    static func emptyTrash() -> String? {
        let script = NSAppleScript(source: "tell application \"Finder\" to empty trash")
        var err: NSDictionary?
        script?.executeAndReturnError(&err)
        if Capabilities.automationDenied(err) {
            return String(localized: "Tidy for Mac isn't allowed to control Finder. Allow it under System Settings > Privacy & Security > Automation, or empty the Trash from the Dock.")
        }
        if let err, let msg = err[NSAppleScript.errorMessage] as? String { return msg }
        return nil
    }
}
