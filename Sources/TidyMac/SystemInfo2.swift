//  System facts, batch two: Wi-Fi and DNS, sync clients, Time Machine, vendor update feeds,
//  Mach-O architecture parsing (for the Rosetta card), menu bar apps and widgets, printers,
//  power and sleep (pmset), and the disk benchmark. Same rules as SystemInfo.swift: stock
//  tools, no privileges, plain values out.

import Foundation
import AppKit
import Darwin

// MARK: - Types for the second batch of optimisers

struct NetworkInfo: Sendable {
    var ssid: String?
    var channel: String?
    var band: String?          // "2.4 GHz", "5 GHz", "6 GHz"
    var phyMode: String?
    var signal: Int?           // dBm
    var noise: Int?
    var txRate: Int?           // Mbps
    var fasterBandAvailable: Bool
    var dnsMillis: Int?
    var gateway: String?
    var gatewayMillis: Double?

    var signalLabel: String {
        guard let s = signal else { return String(localized: "Not on Wi-Fi") }
        if s >= -50 { return String(localized: "Excellent") }
        if s >= -60 { return String(localized: "Good") }
        if s >= -70 { return String(localized: "Fair") }
        return String(localized: "Weak")
    }
}

struct SyncStatus: Identifiable, Sendable {
    var name: String
    var bundleID: String?
    var processName: String
    var running: Bool
    var cpuNow: Double
    var stuck: Bool
    var id: String { processName }
}

struct TimeMachineInfo: Sendable {
    var configured: Bool
    var destination: String?
    var lastBackup: Date?
    var localSnapshots: [Date]
}

struct AppUpdateInfo: Identifiable, Sendable {
    var name: String
    var path: String
    var installed: String
    var latest: String?
    var source: String         // "App Store", "Sparkle", "Google", "Checks itself"
    var status: Status
    enum Status: Sendable { case upToDate, outdated, unknown, appStore }
    var id: String { path }
}

struct RosettaApp: Identifiable, Sendable {
    var name: String
    var path: String
    var id: String { path }
}

struct PrinterInfo: Identifiable, Sendable {
    var name: String
    var isDefault: Bool
    var state: String          // idle, printing, disabled, paused
    var reason: String?
    var jobs: Int
    var uri: String?
    var id: String { name }
}

struct PowerInfo: Sendable {
    var onBattery: Bool?
    var percent: Int?
    var charging: Bool?
    var lowPowerMode: Bool?
    var displaySleepMinutes: Int?
    var settings: [String: String]   // raw pmset -g values
}

struct SleepInfo: Sendable {
    struct Assertion: Identifiable, Sendable {
        var process: String
        var type: String
        var reason: String?
        var id: String { process + type + (reason ?? "") }
    }
    struct Wake: Identifiable, Sendable {
        var when: String
        var reason: String
        var friendly: String
        var id: String { when + reason }
    }
    var assertions: [Assertion]
    var scheduled: [String]
    var recentWakes: [Wake]
    var wakeForNetwork: Bool?
    var powerNap: Bool?
    var proximityWake: Bool?
    var tcpKeepAlive: Bool?
}

struct VolumeBench: Identifiable, Sendable {
    var path: String
    var name: String
    var isInternal: Bool
    var writeMBs: Double?
    var readMBs: Double?
    var id: String { path }

    var verdict: String {
        guard let r = readMBs else { return "" }
        if r >= 1500 { return String(localized: "Very fast. Nothing here is holding you back.") }
        if r >= 400 { return String(localized: "Fast. Fine for anything.") }
        if r >= 120 { return String(localized: "Moderate. Fine for documents, slow for big photo or video libraries.") }
        return String(localized: "Slow. A spinning disk or a slow USB stick. Anything stored here will feel sluggish.")
    }
}

// MARK: - Second batch of system information

enum SystemInfo2 {

    // MARK: 1. Wi-Fi and DNS

    static func network() -> NetworkInfo {
        var info = NetworkInfo(fasterBandAvailable: false)
        let json = SystemInfo.run("/usr/sbin/system_profiler", ["SPAirPortDataType", "-json"], timeout: 20)
        if let data = json.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let items = obj["SPAirPortDataType"] as? [[String: Any]],
           let ifaces = items.first?["spairport_airport_interfaces"] as? [[String: Any]] {
            for iface in ifaces {
                guard let cur = iface["spairport_current_network_information"] as? [String: Any] else { continue }
                info.ssid = cur["_name"] as? String
                info.channel = cur["spairport_network_channel"] as? String
                info.phyMode = cur["spairport_network_phymode"] as? String
                if let rate = cur["spairport_network_rate"] as? Int { info.txRate = rate }
                if let sn = cur["spairport_signal_noise"] as? String {
                    let nums = sn.split(separator: "/").compactMap { Int($0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " dBm", with: "")) }
                    if nums.count == 2 { info.signal = nums[0]; info.noise = nums[1] }
                }
                if let ch = info.channel {
                    if ch.contains("6GHz") { info.band = "6 GHz" }
                    else if ch.contains("5GHz") { info.band = "5 GHz" }
                    else if ch.contains("2GHz") || (Int(ch.split(separator: " ").first ?? "") ?? 99) <= 14 { info.band = "2.4 GHz" }
                    else { info.band = "5 GHz" }
                }
                if info.band == "2.4 GHz", let ssid = info.ssid,
                   let others = iface["spairport_airport_other_local_wireless_networks"] as? [[String: Any]] {
                    info.fasterBandAvailable = others.contains { ($0["_name"] as? String) == ssid && (($0["spairport_network_channel"] as? String) ?? "").contains("5GHz") }
                }
                break
            }
        }
        // DNS: time a lookup
        let t0 = Date()
        let dig = SystemInfo.run("/usr/bin/dig", ["+time=2", "+tries=1", "www.apple.com"], timeout: 6)
        if let line = dig.split(separator: "\n").first(where: { $0.contains("Query time:") }),
           let ms = Int(line.replacingOccurrences(of: ";; Query time: ", with: "").replacingOccurrences(of: " msec", with: "").trimmingCharacters(in: .whitespaces)) {
            info.dnsMillis = ms
        } else if !dig.isEmpty {
            info.dnsMillis = Int(Date().timeIntervalSince(t0) * 1000)
        }
        // Gateway ping
        let route = SystemInfo.run("/sbin/route", ["-n", "get", "default"], timeout: 5)
        if let gw = route.split(separator: "\n").first(where: { $0.contains("gateway:") })?.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) {
            info.gateway = gw
            let ping = SystemInfo.run("/sbin/ping", ["-c", "3", "-i", "0.3", "-W", "1000", "-q", gw], timeout: 6)
            if let line = ping.split(separator: "\n").first(where: { $0.contains("round-trip") }),
               let stats = line.split(separator: "=").last?.trimmingCharacters(in: .whitespaces).split(separator: "/"), stats.count >= 2,
               let avg = Double(stats[1]) { info.gatewayMillis = avg }
        }
        return info
    }

    // MARK: 2. Sync clients

    static let syncClients: [(name: String, bundleID: String?, process: String)] = [
        ("iCloud Drive", nil, "bird"),
        ("Dropbox", "com.getdropbox.dropbox", "Dropbox"),
        ("Google Drive", "com.google.drivefs", "Google Drive"),
        ("OneDrive", "com.microsoft.OneDrive", "OneDrive"),
    ]

    /// "Stuck" means five consecutive samples (about 20 s at the live refresh rate) at 25% CPU
    /// or more. A single busy sample is normal after a big file lands; sustained churn is not.
    static func sync(_ procs: [ProcInfo], history: [String: [Double]]) -> [SyncStatus] {
        syncClients.map { c in
            let matching = procs.filter { URL(fileURLWithPath: $0.command).lastPathComponent == c.process || $0.command.contains("/\(c.process).app/") }
            let cpu = matching.reduce(0) { $0 + $1.cpu }
            let samples = history[c.process] ?? []
            let stuck = samples.count >= 5 && samples.suffix(5).allSatisfy { $0 >= 25 }
            return SyncStatus(name: c.name, bundleID: c.bundleID, processName: c.process, running: !matching.isEmpty, cpuNow: cpu, stuck: stuck)
        }
    }

    static func restartSync(_ s: SyncStatus) -> String? {
        if let bid = s.bundleID {
            for r in NSRunningApplication.runningApplications(withBundleIdentifier: bid) { r.terminate() }
            Thread.sleep(forTimeInterval: 2)
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
            return nil
        }
        // iCloud's bird daemon relaunches on its own after a nudge.
        _ = SystemInfo.run("/usr/bin/killall", [s.processName], timeout: 5)
        return nil
    }

    // MARK: 3. Time Machine

    static func timeMachine() -> TimeMachineInfo {
        let dest = SystemInfo.run("/usr/bin/tmutil", ["destinationinfo"], timeout: 15)
        let configured = !dest.contains("No destinations configured") && !dest.isEmpty
        let name = dest.split(separator: "\n").first(where: { $0.contains("Name") })?.split(separator: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
        let latest = SystemInfo.run("/usr/bin/tmutil", ["latestbackup"], timeout: 15).trimmingCharacters(in: .whitespacesAndNewlines)
        let stamp: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd-HHmmss"; f.locale = Locale(identifier: "en_US_POSIX"); return f }()
        var last: Date?
        if let comp = latest.split(separator: "/").last, let m = comp.range(of: #"\d{4}-\d{2}-\d{2}-\d{6}"#, options: .regularExpression) {
            last = stamp.date(from: String(comp[m]))
        }
        let snaps = SystemInfo.run("/usr/bin/tmutil", ["listlocalsnapshots", "/"], timeout: 15).split(separator: "\n")
            .compactMap { line -> Date? in
                guard let m = line.range(of: #"\d{4}-\d{2}-\d{2}-\d{6}"#, options: .regularExpression) else { return nil }
                return stamp.date(from: String(line[m]))
            }
        return TimeMachineInfo(configured: configured, destination: name, lastBackup: last, localSnapshots: snaps.sorted())
    }

    // MARK: 4. App update sweep

    static func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
        let pa = a.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        let pb = b.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    static func fetch(_ url: String, timeout: TimeInterval = 10) -> Data? {
        guard let u = URL(string: url) else { return nil }
        let sem = DispatchSemaphore(value: 0)
        var out: Data?
        var req = URLRequest(url: u, timeoutInterval: timeout)
        req.setValue("TidyMac/1.0", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { d, _, _ in out = d; sem.signal() }.resume()
        _ = sem.wait(timeout: .now() + timeout + 2)
        return out
    }

    static func appUpdates() -> [AppUpdateInfo] {
        var out: [AppUpdateInfo] = []
        for u in Scanner.contents(URL(fileURLWithPath: "/Applications")) where u.pathExtension == "app" {
            guard let info = NSDictionary(contentsOf: u.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
                  let bid = info["CFBundleIdentifier"] as? String, !bid.hasPrefix("com.apple.") else { continue }
            let name = u.deletingPathExtension().lastPathComponent
            let installed = info["CFBundleShortVersionString"] as? String ?? info["CFBundleVersion"] as? String ?? "?"
            if FileManager.default.fileExists(atPath: u.appendingPathComponent("Contents/_MASReceipt/receipt").path) {
                out.append(AppUpdateInfo(name: name, path: u.path, installed: installed, latest: nil, source: "App Store", status: .appStore))
                continue
            }
            var latest: String?
            var source = String(localized: "Checks itself")
            if bid == "com.google.Chrome" {
                source = "Google"
                if let d = fetch("https://versionhistory.googleapis.com/v1/chrome/platforms/mac/channels/stable/versions?pageSize=1"),
                   let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                   let v = (j["versions"] as? [[String: Any]])?.first?["version"] as? String { latest = v }
            } else if let feed = info["SUFeedURL"] as? String, let d = fetch(feed), let xml = String(data: d, encoding: .utf8) {
                source = "Sparkle"
                // First item in an appcast is normally the newest.
                let patterns = [#"sparkle:shortVersionString="([^"]+)""#, #"<sparkle:shortVersionString>([^<]+)<"#, #"sparkle:version="([^"]+)""#, #"<sparkle:version>([^<]+)<"#]
                for p in patterns {
                    if let m = xml.range(of: p, options: .regularExpression) {
                        let s = String(xml[m])
                        if let q = s.range(of: #"[\d][\d\.]*"#, options: .regularExpression) { latest = String(s[q]); break }
                    }
                }
            }
            let status: AppUpdateInfo.Status
            if let l = latest { status = compareVersions(installed, l) == .orderedAscending ? .outdated : .upToDate } else { status = .unknown }
            out.append(AppUpdateInfo(name: name, path: u.path, installed: installed, latest: latest, source: source, status: status))
        }
        let order: [AppUpdateInfo.Status] = [.outdated, .upToDate, .unknown, .appStore]
        return out.sorted { (order.firstIndex(of: $0.status) ?? 9, $0.name) < (order.firstIndex(of: $1.status) ?? 9, $1.name) }
    }

    // MARK: 5. Rosetta / Intel-only apps

    static var isAppleSilicon: Bool { Capabilities.isAppleSilicon }

    /// Reads the Mach-O header to see which CPU types an executable contains, without lipo
    /// (which only ships with the developer tools). Two layouts:
    ///   - Fat binary: big-endian magic 0xCAFEBABE (32-bit offsets) or 0xCAFEBABF (64-bit),
    ///     a count, then fixed-size fat_arch entries whose first field is the cputype.
    ///   - Thin binary: little-endian magic 0xFEEDFACF (64-bit) or 0xFEEDFACE, cputype at offset 4.
    /// cputype & 0x00FFFFFF is 7 for x86_64 and 12 for arm64 (the high byte is the 64-bit flag).
    static func architectures(of exec: URL) -> Set<String> {
        guard let h = try? FileHandle(forReadingFrom: exec), let head = try? h.read(upToCount: 4096), head.count >= 8 else { return [] }
        try? h.close()
        func be32(_ o: Int) -> UInt32 { head.subdata(in: o..<o+4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian } }
        func le32(_ o: Int) -> UInt32 { head.subdata(in: o..<o+4).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian } }
        func name(_ cpu: UInt32) -> String? {
            switch cpu & 0x00FFFFFF { case 7: return "x86_64"; case 12: return "arm64"; default: return nil }
        }
        var archs = Set<String>()
        let magic = be32(0)
        if magic == 0xCAFEBABE || magic == 0xCAFEBABF {      // fat binary
            let n = Int(be32(4))
            let entry = magic == 0xCAFEBABE ? 20 : 32
            for i in 0..<min(n, 8) where 8 + i * entry + 4 <= head.count {
                if let a = name(be32(8 + i * entry)) { archs.insert(a) }
            }
        } else if le32(0) == 0xFEEDFACF || le32(0) == 0xFEEDFACE {   // thin, little-endian
            if let a = name(le32(4)) { archs.insert(a) }
        }
        return archs
    }

    static func rosettaApps() -> [RosettaApp] {
        guard isAppleSilicon else { return [] }
        var out: [RosettaApp] = []
        for u in Scanner.contents(URL(fileURLWithPath: "/Applications")) where u.pathExtension == "app" {
            guard let info = NSDictionary(contentsOf: u.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
                  let exe = info["CFBundleExecutable"] as? String else { continue }
            let archs = architectures(of: u.appendingPathComponent("Contents/MacOS/\(exe)"))
            if !archs.isEmpty && !archs.contains("arm64") {
                out.append(RosettaApp(name: u.deletingPathExtension().lastPathComponent, path: u.path))
            }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: 6. Menu bar apps and widgets

    @MainActor
    static func menuBarApps(_ procs: [ProcInfo]) -> [AppLoad] {
        let byPid = Dictionary(uniqueKeysWithValues: procs.map { ($0.pid, $0) })
        var out: [AppLoad] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .accessory {
            guard let url = app.bundleURL, app.bundleIdentifier != Bundle.main.bundleIdentifier else { continue }
            let mine = procs.filter { $0.command.hasPrefix(url.path) }
            let mem = mine.isEmpty ? (byPid[app.processIdentifier]?.rss ?? 0) : mine.reduce(0) { $0 + $1.rss }
            let cpu = mine.isEmpty ? (byPid[app.processIdentifier]?.cpu ?? 0) : mine.reduce(0) { $0 + $1.cpu }
            out.append(AppLoad(id: url.path, name: app.localizedName ?? url.lastPathComponent, bundlePath: url.path, cpu: cpu, memory: mem, processes: max(mine.count, 1), isApp: true))
        }
        return out.sorted { $0.memory > $1.memory }
    }

    /// Running widget extensions. `isApp` is true for third-party widgets (removable); Apple's built-ins are
    /// folded into one summary entry because they can't be removed and cost little each.
    static func widgets(_ procs: [ProcInfo]) -> [AppLoad] {
        var groups: [String: AppLoad] = [:]
        var apple = AppLoad(id: "apple-widgets", name: String(localized: "Apple's built-in widgets"), bundlePath: nil, cpu: 0, memory: 0, processes: 0, isApp: false)
        for p in procs where p.command.contains(".appex/") && p.command.lowercased().contains("widget") {
            guard let r = p.command.range(of: ".appex/") else { continue }
            let path = String(p.command[..<r.lowerBound]) + ".appex"
            if path.hasPrefix("/System/") || path.hasPrefix("/usr/") {
                apple.cpu += p.cpu; apple.memory += p.rss; apple.processes += 1
                continue
            }
            let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: "WidgetExtension", with: "").replacingOccurrences(of: "Widget", with: "")
            var g = groups[path] ?? AppLoad(id: path, name: name.isEmpty ? URL(fileURLWithPath: path).lastPathComponent : name, bundlePath: path, cpu: 0, memory: 0, processes: 0, isApp: true)
            g.cpu += p.cpu; g.memory += p.rss; g.processes += 1
            groups[path] = g
        }
        var out = groups.values.sorted { $0.memory > $1.memory }
        if apple.processes > 0 { out.append(apple) }
        return out
    }

    // MARK: 7. Printers

    static func printers() -> [PrinterInfo] {
        let p = SystemInfo.run("/usr/bin/lpstat", ["-p"], timeout: 10)
        let d = SystemInfo.run("/usr/bin/lpstat", ["-d"], timeout: 10)
        let v = SystemInfo.run("/usr/bin/lpstat", ["-v"], timeout: 10)
        let o = SystemInfo.run("/usr/bin/lpstat", ["-o"], timeout: 10)
        let defaultName = d.split(separator: ":").last?.trimmingCharacters(in: .whitespacesAndNewlines)
        var uris: [String: String] = [:]
        for line in v.split(separator: "\n") {
            // device for Name: uri
            guard line.hasPrefix("device for "), let colon = line.firstIndex(of: ":") else { continue }
            let name = line[line.index(line.startIndex, offsetBy: 11)..<colon]
            uris[String(name)] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        var jobs: [String: Int] = [:]
        for line in o.split(separator: "\n") {
            if let first = line.split(separator: " ").first, let dash = first.lastIndex(of: "-") {
                jobs[String(first[..<dash]), default: 0] += 1
            }
        }
        var out: [PrinterInfo] = []
        var current: PrinterInfo?
        for line in p.split(separator: "\n") {
            if line.hasPrefix("printer ") {
                if let c = current { out.append(c) }
                let parts = line.split(separator: " ")
                let name = parts.count > 1 ? String(parts[1]) : "?"
                let state = line.contains("disabled") ? "disabled" : (line.contains("printing") ? "printing" : (line.contains("paused") ? "paused" : "idle"))
                current = PrinterInfo(name: name, isDefault: name == defaultName, state: state, reason: nil, jobs: jobs[name] ?? 0, uri: uris[name])
            } else if var c = current, line.trimmingCharacters(in: .whitespaces).isEmpty == false {
                c.reason = line.trimmingCharacters(in: .whitespaces)
                current = c
            }
        }
        if let c = current { out.append(c) }
        return out
    }

    static func clearJobs(_ printer: String) -> String? {
        let r = SystemInfo.run("/usr/bin/cancel", ["-a", printer], timeout: 10)
        return r.isEmpty ? nil : r
    }

    static func removePrinter(_ printer: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/lpadmin")
        p.arguments = ["-x", printer]
        let err = Pipe(); p.standardError = err; p.standardOutput = Pipe()
        do { try p.run() } catch { return error.localizedDescription }
        p.waitUntilExit()
        let msg = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return p.terminationStatus == 0 ? nil : (msg.isEmpty ? String(localized: "Needs an administrator. Remove it in Printers & Scanners settings instead.") : msg)
    }

    // MARK: 8 & 9. Power, sleep and wake

    static func pmsetSettings() -> [String: String] {
        var out: [String: String] = [:]
        for line in SystemInfo.run("/usr/bin/pmset", ["-g"], timeout: 10).split(separator: "\n") {
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
            if parts.count == 2 { out[String(parts[0])] = String(parts[1]).trimmingCharacters(in: .whitespaces) }
        }
        return out
    }

    static func power() -> PowerInfo {
        let batt = SystemInfo.run("/usr/bin/pmset", ["-g", "batt"], timeout: 10)
        let s = pmsetSettings()
        var info = PowerInfo(onBattery: nil, percent: nil, charging: nil, lowPowerMode: (s["lowpowermode"]).map { $0 == "1" },
                             displaySleepMinutes: s["displaysleep"].flatMap { Int($0) }, settings: s)
        if batt.contains("Battery Power") { info.onBattery = true } else if batt.contains("AC Power") { info.onBattery = false }
        if let m = batt.range(of: #"(\d+)%"#, options: .regularExpression) { info.percent = Int(batt[m].dropLast()) }
        if batt.contains("charging") && !batt.contains("discharging") { info.charging = true } else if batt.contains("discharging") { info.charging = false }
        return info
    }

    static func friendlyWake(_ reason: String) -> String {
        let r = reason.lowercased()
        if r.contains("lid") { return String(localized: "You opened the lid") }
        if r.contains("usb-c_plug") || r.contains("usb") { return String(localized: "Something was plugged in or unplugged") }
        if r.contains("dasd") || r.contains("sleepservice") || r.contains("backgroundtask") { return String(localized: "Scheduled background task (normal)") }
        if r.contains("outboxnotempty") || r.contains("smc.sysstate") { return String(localized: "System housekeeping (normal)") }
        if r.contains("powerbutton") || r.contains("power button") { return String(localized: "Power button") }
        if r.contains("acattach") || r.contains("ac attach") { return String(localized: "Charger plugged in") }
        if r.contains("rtc") || r.contains("maintenance") || r.contains("darkwake") { return String(localized: "Scheduled maintenance wake (normal)") }
        if r.contains("tcpkeepalive") || r.contains("notification") || r.contains("network") || r.contains("wifi") { return String(localized: "Network activity woke it") }
        if r.contains("bluetooth") || r.contains("bt ") || r.hasPrefix("bt") { return String(localized: "A Bluetooth device woke it") }
        if r.contains("hid") || r.contains("useractivity") || r.contains("keyboard") || r.contains("trackpad") || r.contains("mouse") { return String(localized: "Keyboard, mouse or trackpad") }
        if r.contains("proximity") { return String(localized: "Your iPhone or Watch came near") }
        return reason
    }

    static func sleep() -> SleepInfo {
        let s = pmsetSettings()
        // Assertions: who is keeping the Mac awake right now
        var assertions: [SleepInfo.Assertion] = []
        let a = SystemInfo.run("/usr/bin/pmset", ["-g", "assertions"], timeout: 10)
        for line in a.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("pid "), let paren = t.firstIndex(of: "("), let close = t.firstIndex(of: ")") else { continue }
            let proc = String(t[t.index(after: paren)..<close])
            let types = ["PreventUserIdleSystemSleep", "PreventSystemSleep", "PreventUserIdleDisplaySleep", "NoIdleSleepAssertion", "NoDisplaySleepAssertion"]
            guard let type = types.first(where: { t.contains($0) }) else { continue }
            var reason: String?
            if let n = t.range(of: "named: \"") { reason = String(t[n.upperBound...]).replacingOccurrences(of: "\"", with: "") }
            assertions.append(SleepInfo.Assertion(process: proc, type: type, reason: reason))
        }
        // Scheduled events
        let sched = SystemInfo.run("/usr/bin/pmset", ["-g", "sched"], timeout: 10).split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("Scheduled power events") && !$0.contains("No scheduled") }
        // Recent wakes from the power log
        // pmset log rows: "<date> <time> <tz> <Domain padded>\t<message>". Only the Wake and DarkWake domains matter here.
        let log = SystemInfo.run("/usr/bin/pmset", ["-g", "log"], timeout: 20)
        var wakes: [SleepInfo.Wake] = []
        for line in log.split(separator: "\n").reversed() {
            let cols = line.split(separator: "\t", maxSplits: 1)
            guard cols.count == 2 else { continue }
            let head = cols[0].split(separator: " ", omittingEmptySubsequences: true)
            guard head.count >= 4 else { continue }
            let domain = String(head[3])
            guard domain == "Wake" || domain == "DarkWake" else { continue }
            let msg = String(cols[1])
            let when = "\(head[0]) \(head[1].prefix(5))"
            var reason = msg
            if let r = msg.range(of: "due to ") {
                reason = String(msg[r.upperBound...])
                if let end = reason.range(of: " Using") ?? reason.range(of: ":") { reason = String(reason[..<end.lowerBound]) }
            }
            reason = reason.trimmingCharacters(in: .whitespaces)
            if reason.count > 60 { reason = String(reason.prefix(60)) }
            let friendly = friendlyWake(reason) + (domain == "DarkWake" ? String(localized: " (brief, screen stayed off)") : "")
            wakes.append(SleepInfo.Wake(when: when, reason: reason, friendly: friendly))
            if wakes.count >= 6 { break }
        }
        return SleepInfo(assertions: assertions, scheduled: sched, recentWakes: wakes,
                         wakeForNetwork: s["womp"].map { $0 == "1" }, powerNap: s["powernap"].map { $0 == "1" },
                         proximityWake: s["proximitywake"].map { $0 == "1" }, tcpKeepAlive: s["tcpkeepalive"].map { $0 == "1" })
    }

    // MARK: 10. Disk speed

    static func volumes() -> [VolumeBench] {
        var out = [VolumeBench(path: NSHomeDirectory(), name: String(localized: "Startup disk"), isInternal: true)]
        for u in Scanner.contents(URL(fileURLWithPath: "/Volumes")) {
            guard let v = try? u.resourceValues(forKeys: [.volumeIsInternalKey, .volumeIsRootFileSystemKey, .volumeIsReadOnlyKey, .isSymbolicLinkKey, .volumeIsBrowsableKey]),
                  v.isSymbolicLink != true, v.volumeIsRootFileSystem != true, v.volumeIsReadOnly != true, v.volumeIsBrowsable != false else { continue }
            out.append(VolumeBench(path: u.path, name: u.lastPathComponent, isInternal: v.volumeIsInternal ?? false))
        }
        return out
    }

    /// Writes and reads back 256 MB with the cache bypassed. Cleans up after itself.
    /// F_NOCACHE on both handles bypasses the unified buffer cache so the read phase measures the
    /// drive, not RAM. The write phase ends with synchronize() so buffered data is actually on disk
    /// before the clock stops. 256 MB is enough to get past any drive's SLC cache on a quick test
    /// while staying under a couple of seconds on a slow USB stick.
    static func benchmark(_ volumePath: String) -> (write: Double, read: Double)? {
        let dir = URL(fileURLWithPath: volumePath).appendingPathComponent(volumePath == NSHomeDirectory() ? "Library/Caches" : "")
        let file = dir.appendingPathComponent(".tidymac-speedtest-\(getpid())")
        let chunk = Data(repeating: 0x5A, count: 4 * 1024 * 1024)
        let chunks = 64
        defer { try? FileManager.default.removeItem(at: file) }
        guard FileManager.default.createFile(atPath: file.path, contents: nil), let wh = try? FileHandle(forWritingTo: file) else { return nil }
        _ = fcntl(wh.fileDescriptor, F_NOCACHE, 1)
        let t0 = Date()
        for _ in 0..<chunks { try? wh.write(contentsOf: chunk) }
        try? wh.synchronize()
        try? wh.close()
        let write = Double(chunks * chunk.count) / 1_048_576 / max(Date().timeIntervalSince(t0), 0.001)
        guard let rh = try? FileHandle(forReadingFrom: file) else { return nil }
        _ = fcntl(rh.fileDescriptor, F_NOCACHE, 1)
        let t1 = Date()
        var total = 0
        while let d = try? rh.read(upToCount: chunk.count), !d.isEmpty { total += d.count }
        try? rh.close()
        let read = Double(total) / 1_048_576 / max(Date().timeIntervalSince(t1), 0.001)
        return (write, read)
    }
}
