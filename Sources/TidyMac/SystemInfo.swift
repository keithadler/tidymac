//  System facts for the Speed tab, batch one. Every function shells out to a stock macOS tool
//  (ps, launchctl, system_profiler, pmset, softwareupdate) or reads a public API, parses the
//  result, and returns plain Sendable values. Nothing here needs privileges.
//
//  run() is the one process wrapper: it captures stdout, discards stderr, and kills the child
//  on timeout so a hung tool can never hang the app.

import Foundation
import AppKit
import Darwin

// MARK: - Types

struct ProcInfo: Sendable {
    var pid: Int32
    var cpu: Double
    var rss: Int64        // bytes
    var command: String   // full path when available
}

struct AppLoad: Identifiable, Sendable {
    var id: String
    var name: String
    var bundlePath: String?
    var cpu: Double
    var memory: Int64
    var processes: Int
    var isApp: Bool
}

struct MemoryInfo: Sendable {
    var total: Int64
    var used: Int64
    var pressure: Int   // 1 normal, 2 warning, 4 critical
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
    var pressureLabel: String {
        switch pressure {
        case 4: return String(localized: "Critical")
        case 2: return String(localized: "Under pressure")
        default: return String(localized: "Fine")
        }
    }
}

struct LoginItem: Identifiable, Sendable {
    var name: String
    var path: String
    var id: String { name }
}

struct AgentInfo: Identifiable, Sendable {
    var plistPath: String
    var label: String
    var program: String
    var vendor: String
    var loaded: Bool
    var runAtLoad: Bool
    var system: Bool          // lives in /Library, needs an administrator to change
    var disabledByTidy: Bool
    var cpu: Double
    var memory: Int64
    var id: String { plistPath }
}

struct BrowserProfile: Identifiable, Sendable {
    var id: String
    var name: String
    var siteData: Int64
    var cachePaths: [String]
}

struct BrowserExtension: Identifiable, Sendable {
    var id: String
    var name: String
    var size: Int64
    var profile: String
}

struct BrowserInfo: Identifiable, Sendable {
    var name: String
    var bundleID: String
    var running: Bool
    var profiles: [BrowserProfile]
    var extensions: [BrowserExtension]
    var id: String { bundleID }
    var total: Int64 { profiles.reduce(0) { $0 + $1.siteData } }
}

struct BatteryInfo: Sendable {
    var cycles: Int?
    var healthPercent: Int?
    var condition: String?
}

struct HealthReport: Sendable {
    var battery: BatteryInfo?
    var smartOK: Bool?
    var uptimeDays: Double
    var thermal: String
    var cpuSpeedLimit: Int?
    var osVersion: String
}

enum Verdict: Sendable { case good, watch, act }

// MARK: - System information, all without privileges

enum SystemInfo {

    static func run(_ path: String, _ args: [String], timeout: TimeInterval = 30) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return "" }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        return String(decoding: data, as: UTF8.self)
    }

    static func sysctlInt(_ name: String) -> Int? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }

    // MARK: Processes

    static func processes() -> [ProcInfo] {
        let text = run("/bin/ps", ["-axo", "pid=,pcpu=,rss=,comm="], timeout: 10)
        var out: [ProcInfo] = []
        for line in text.split(separator: "\n") {
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let pid = Int32(parts[0]), let cpu = Double(parts[1]), let rssKB = Int64(parts[2]) else { continue }
            out.append(ProcInfo(pid: pid, cpu: cpu, rss: rssKB * 1024, command: String(parts[3])))
        }
        return out
    }

    /// Groups processes by the outermost .app bundle they belong to, so Chrome's 60 helper
    /// processes show as one row. The *first* ".app/" in the path is the outer bundle; helpers
    /// live in nested .app bundles inside it.
    static func appLoads(_ procs: [ProcInfo]) -> [AppLoad] {
        var groups: [String: AppLoad] = [:]
        for p in procs {
            let key: String
            let name: String
            let bundle: String?
            if let r = p.command.range(of: ".app/") {
                let path = String(p.command[..<r.lowerBound]) + ".app"
                key = path
                name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                bundle = path
            } else {
                let base = URL(fileURLWithPath: p.command).lastPathComponent
                key = "proc:" + base
                name = base
                bundle = nil
            }
            var g = groups[key] ?? AppLoad(id: key, name: name, bundlePath: bundle, cpu: 0, memory: 0, processes: 0, isApp: bundle != nil)
            g.cpu += p.cpu
            g.memory += p.rss
            g.processes += 1
            groups[key] = g
        }
        return groups.values.sorted { $0.memory > $1.memory }
    }

    /// "Used" follows Activity Monitor's definition: active + wired + compressed pages. Free and
    /// inactive pages are left out because macOS fills them with cache on purpose; counting them
    /// would make every Mac look full. Pressure comes from the kernel's own memorystatus level
    /// (1 normal, 2 warning, 4 critical), which is what the coloured graph in Activity Monitor uses.
    static func memory() -> MemoryInfo {
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        var used: Int64 = 0
        if result == KERN_SUCCESS {
            let page = Int64(vm_kernel_page_size)
            used = (Int64(stats.active_count) + Int64(stats.wire_count) + Int64(stats.compressor_page_count)) * page
        }
        let pressure = sysctlInt("kern.memorystatus_vm_pressure_level") ?? 1
        return MemoryInfo(total: total, used: used, pressure: pressure)
    }

    /// Plain-language explanation when macOS itself is busy in the background.
    static func backgroundActivity(_ procs: [ProcInfo]) -> String? {
        let known: [(String, String)] = [
            ("mds_stores", String(localized: "Spotlight is indexing your files")),
            ("mdworker", String(localized: "Spotlight is indexing your files")),
            ("photoanalysisd", String(localized: "Photos is analysing your pictures for faces and places")),
            ("photolibraryd", String(localized: "Photos is organising its library")),
            ("mediaanalysisd", String(localized: "macOS is analysing photos and videos")),
            ("backupd", String(localized: "Time Machine is backing up")),
            ("bird", String(localized: "iCloud Drive is syncing")),
            ("cloudd", String(localized: "iCloud is syncing")),
            ("softwareupdated", String(localized: "A macOS update is downloading or preparing")),
            ("kernel_task", String(localized: "The system is keeping the chip cool")),
        ]
        for p in procs where p.cpu >= 15 {
            let base = URL(fileURLWithPath: p.command).lastPathComponent
            if let k = known.first(where: { base.hasPrefix($0.0) }) { return k.1 }
        }
        return nil
    }

    static var uptimeDays: Double { ProcessInfo.processInfo.systemUptime / 86400 }

    // MARK: Login items (legacy list via System Events) and launch agents

    /// Legacy login items via System Events. Returns the list plus a flag when macOS refused the
    /// Apple Event (the user declined the Automation prompt), so the UI can show how to allow it.
    static func loginItems() -> (items: [LoginItem], denied: Bool) {
        var denied = false
        func list(_ prop: String) -> [String] {
            let script = NSAppleScript(source: "tell application \"System Events\" to get \(prop) of every login item")
            var err: NSDictionary?
            guard let d = script?.executeAndReturnError(&err) else {
                if Capabilities.automationDenied(err) { denied = true }
                return []
            }
            return (1...max(d.numberOfItems, 1)).compactMap { d.numberOfItems == 0 ? nil : d.atIndex($0)?.stringValue }
        }
        let names = list("name"), paths = list("path")
        return (names.enumerated().map { i, n in LoginItem(name: n, path: i < paths.count ? paths[i] : "") }, denied)
    }

    static func removeLoginItem(_ name: String) -> String? {
        let escaped = name.replacingOccurrences(of: "\"", with: "\\\"")
        let script = NSAppleScript(source: "tell application \"System Events\" to delete login item \"\(escaped)\"")
        var err: NSDictionary?
        script?.executeAndReturnError(&err)
        return err?[NSAppleScript.errorMessage] as? String
    }

    static let disabledAgentsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent("Tidy for Mac/Disabled Agents", isDirectory: true)

    /// Launch agents from three places: the user's own (~/Library/LaunchAgents, switchable),
    /// all-user ones (/Library/LaunchAgents, read-only here since changing them needs admin),
    /// and the ones Tidy for Mac has parked in its Disabled Agents folder. "Loaded" comes from
    /// `launchctl list`; per-agent CPU and memory come from matching the agent's program path
    /// against the process list.
    static func agents(_ procs: [ProcInfo]) -> [AgentInfo] {
        let loaded = Set(run("/bin/launchctl", ["list"], timeout: 10).split(separator: "\n").dropFirst()
            .compactMap { $0.split(separator: "\t").last.map(String.init) })
        var out: [AgentInfo] = []
        let places: [(URL, Bool, Bool)] = [
            (Scanner.library.appendingPathComponent("LaunchAgents"), false, false),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), true, false),
            (disabledAgentsDir, false, true),
        ]
        for (dir, system, disabled) in places {
            for u in Scanner.contents(dir) where u.pathExtension == "plist" {
                guard let d = NSDictionary(contentsOf: u) as? [String: Any] else { continue }
                let label = d["Label"] as? String ?? u.deletingPathExtension().lastPathComponent
                let program = d["Program"] as? String ?? (d["ProgramArguments"] as? [String])?.first ?? ""
                let vendorParts = label.split(separator: ".")
                let vendor = vendorParts.count >= 2 ? String(vendorParts[1]).capitalized : label
                let matching = procs.filter { !program.isEmpty && $0.command.hasPrefix(program) }
                out.append(AgentInfo(plistPath: u.path, label: label, program: program, vendor: vendor,
                                     loaded: loaded.contains(label), runAtLoad: (d["RunAtLoad"] as? Bool) ?? false,
                                     system: system, disabledByTidy: disabled,
                                     cpu: matching.reduce(0) { $0 + $1.cpu }, memory: matching.reduce(0) { $0 + $1.rss }))
            }
        }
        return out.sorted { ($0.memory, $0.label) > ($1.memory, $1.label) }
    }

    /// Unloads a user launch agent and parks its plist in Tidy for Mac's folder so it can be re-enabled.
    static func disableAgent(_ a: AgentInfo) -> String? {
        guard !a.system else { return String(localized: "This one needs an administrator to change.") }
        let fm = FileManager.default
        try? fm.createDirectory(at: disabledAgentsDir, withIntermediateDirectories: true)
        _ = run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(a.label)"], timeout: 10)
        let dest = disabledAgentsDir.appendingPathComponent(URL(fileURLWithPath: a.plistPath).lastPathComponent)
        do { try fm.moveItem(atPath: a.plistPath, toPath: dest.path); return nil } catch { return error.localizedDescription }
    }

    static func enableAgent(_ a: AgentInfo) -> String? {
        let dest = Scanner.library.appendingPathComponent("LaunchAgents").appendingPathComponent(URL(fileURLWithPath: a.plistPath).lastPathComponent)
        do {
            try FileManager.default.moveItem(atPath: a.plistPath, toPath: dest.path)
            _ = run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", dest.path], timeout: 10)
            return nil
        } catch { return error.localizedDescription }
    }

    // MARK: Browsers (Chromium family; Safari's data is off-limits without Full Disk Access)

    static func browsers() -> [BrowserInfo] {
        let running = Scanner.runningBundleIDs
        let defs: [(name: String, bid: String, support: String, cache: String)] = [
            ("Google Chrome", "com.google.Chrome", "Google/Chrome", "Google/Chrome"),
            ("Microsoft Edge", "com.microsoft.edgemac", "Microsoft Edge", "Microsoft Edge"),
            ("Brave", "com.brave.Browser", "BraveSoftware/Brave-Browser", "BraveSoftware/Brave-Browser"),
            ("Arc", "company.thebrowser.Browser", "Arc/User Data", "Arc"),
            ("Vivaldi", "com.vivaldi.Vivaldi", "Vivaldi", "Vivaldi"),
        ]
        var out: [BrowserInfo] = []
        for d in defs {
            let support = Scanner.library.appendingPathComponent("Application Support/\(d.support)")
            guard FileManager.default.fileExists(atPath: support.path) else { continue }
            let cacheRoot = Scanner.library.appendingPathComponent("Caches/\(d.cache)")
            var profiles: [BrowserProfile] = []
            var exts: [BrowserExtension] = []
            for p in Scanner.contents(support) where FileManager.default.fileExists(atPath: p.appendingPathComponent("Preferences").path) {
                let prefs = (try? JSONSerialization.jsonObject(with: Data(contentsOf: p.appendingPathComponent("Preferences")))) as? [String: Any]
                let pname = ((prefs?["profile"] as? [String: Any])?["name"] as? String) ?? p.lastPathComponent
                let paths = [p.appendingPathComponent("Service Worker/CacheStorage"), p.appendingPathComponent("Code Cache"),
                             cacheRoot.appendingPathComponent(p.lastPathComponent + "/Cache")]
                    .filter { FileManager.default.fileExists(atPath: $0.path) }
                let size = paths.reduce(0) { $0 + Scanner.size(of: $1) }
                profiles.append(BrowserProfile(id: p.path, name: pname, siteData: size, cachePaths: paths.map(\.path)))
                for e in Scanner.contents(p.appendingPathComponent("Extensions")) {
                    guard let ver = Scanner.contents(e).first(where: { FileManager.default.fileExists(atPath: $0.appendingPathComponent("manifest.json").path) }) else { continue }
                    let manifest = (try? JSONSerialization.jsonObject(with: Data(contentsOf: ver.appendingPathComponent("manifest.json")))) as? [String: Any]
                    var name = manifest?["name"] as? String ?? e.lastPathComponent
                    if name.hasPrefix("__MSG_") {
                        let key = name.replacingOccurrences(of: "__MSG_", with: "").replacingOccurrences(of: "__", with: "")
                        let locale = manifest?["default_locale"] as? String ?? "en"
                        for loc in [locale, "en", "en_US"] {
                            if let m = (try? JSONSerialization.jsonObject(with: Data(contentsOf: ver.appendingPathComponent("_locales/\(loc)/messages.json")))) as? [String: Any],
                               let entry = m[key] as? [String: Any] ?? m.first(where: { $0.key.lowercased() == key.lowercased() })?.value as? [String: Any],
                               let msg = entry["message"] as? String { name = msg; break }
                        }
                    }
                    exts.append(BrowserExtension(id: e.path, name: name, size: Scanner.size(of: e), profile: pname))
                }
            }
            guard !profiles.isEmpty else { continue }
            out.append(BrowserInfo(name: d.name, bundleID: d.bid, running: running.contains(d.bid),
                                   profiles: profiles.sorted { $0.siteData > $1.siteData },
                                   extensions: exts.sorted { $0.size > $1.size }))
        }
        return out
    }

    // MARK: Health

    static func battery() -> BatteryInfo? {
        let json = run("/usr/sbin/system_profiler", ["SPPowerDataType", "-json"], timeout: 30)
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = obj["SPPowerDataType"] as? [[String: Any]],
              let bat = items.first(where: { $0["sppower_battery_health_info"] != nil }) else { return nil }
        let health = bat["sppower_battery_health_info"] as? [String: Any]
        let cycles = health?["sppower_battery_cycle_count"] as? Int
        let pct = (health?["sppower_battery_health_maximum_capacity"] as? String).flatMap { Int($0.filter(\.isNumber)) }
        let condition = health?["sppower_battery_health"] as? String
        return BatteryInfo(cycles: cycles, healthPercent: pct, condition: condition)
    }

    static func smartOK() -> Bool? {
        for type in ["SPNVMeDataType", "SPSerialATADataType"] {
            let json = run("/usr/sbin/system_profiler", [type, "-json"], timeout: 30)
            guard let data = json.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = obj[type] as? [[String: Any]] else { continue }
            for controller in items {
                for drive in (controller["_items"] as? [[String: Any]]) ?? [] {
                    if let s = (drive["spnvme_smart_status"] ?? drive["spsata_smart_status"]) as? String {
                        return s.lowercased().contains("verified")
                    }
                }
            }
        }
        return nil
    }

    static func cpuSpeedLimit() -> Int? {
        let text = run("/usr/bin/pmset", ["-g", "therm"], timeout: 10)
        guard let line = text.split(separator: "\n").first(where: { $0.contains("CPU_Speed_Limit") }),
              let v = line.split(separator: "=").last.flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }) else { return nil }
        return v
    }

    static var thermalLabel: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return String(localized: "Cool")
        case .fair: return String(localized: "Warm")
        case .serious: return String(localized: "Hot")
        case .critical: return String(localized: "Very hot")
        @unknown default: return "?"
        }
    }

    static func health() -> HealthReport {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return HealthReport(battery: battery(), smartOK: smartOK(), uptimeDays: uptimeDays, thermal: thermalLabel,
                            cpuSpeedLimit: cpuSpeedLimit(), osVersion: "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)")
    }

    /// Names of pending macOS updates. Slow (network), so call it in the background.
    static func pendingUpdates() -> [String] {
        let text = run("/usr/sbin/softwareupdate", ["-l", "--no-scan"], timeout: 60)
        var names: [String] = []
        for line in text.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("* Label:") { names.append(t.replacingOccurrences(of: "* Label:", with: "").trimmingCharacters(in: .whitespaces)) }
            else if t.hasPrefix("Title:") {
                if let title = t.split(separator: ",").first { names.append(title.replacingOccurrences(of: "Title:", with: "").trimmingCharacters(in: .whitespaces)) }
            }
        }
        return names
    }

    // MARK: Lighter look

    static func accessibilityFlag(_ key: String) -> Bool? {
        CFPreferencesCopyAppValue(key as CFString, "com.apple.universalaccess" as CFString) as? Bool
    }

    // MARK: Actions

    /// Opens a System Settings pane. Pane identifiers have changed between macOS versions, so if
    /// this one isn't recognised the call falls back to opening System Settings itself rather than
    /// doing nothing. Tries the pane id, then the id without its query, then the app.
    static func openSettings(_ pane: String) {
        let ws = NSWorkspace.shared
        if let u = URL(string: "x-apple.systempreferences:\(pane)"), ws.open(u) { return }
        let bare = pane.split(separator: "?").first.map(String.init) ?? pane
        if bare != pane, let u = URL(string: "x-apple.systempreferences:\(bare)"), ws.open(u) { return }
        if let app = ws.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
            ws.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    static func restart() -> String? {
        let script = NSAppleScript(source: "tell application \"System Events\" to restart")
        var err: NSDictionary?
        script?.executeAndReturnError(&err)
        return err?[NSAppleScript.errorMessage] as? String
    }
}
