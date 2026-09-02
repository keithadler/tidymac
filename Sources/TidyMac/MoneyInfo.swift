//  Data for the Money tab: subscriptions that look unused, overlapping cloud drives, the
//  "don't buy more storage yet" sum, an internet speed test, the battery-service decision, the
//  "is this Mac done" verdict, built-in alternatives to paid apps, and boot timing.
//  Same rules as the rest: stock tools, no privileges, plain values out, and never a guess shown
//  as a fact. Prices are quoted as "typical" and dated, because they change.

import Foundation
import AppKit

// MARK: - Types

struct SubscriptionApp: Identifiable, Sendable {
    var name: String
    var path: String
    var vendor: String
    var lastUsed: Date?
    var manageURL: String
    var note: String
    var id: String { path }
    var daysIdle: Int? { lastUsed.map { Int(Date().timeIntervalSince($0) / 86400) } }
}

struct CloudDrive: Identifiable, Sendable {
    var name: String
    var installed: Bool
    var running: Bool
    var localBytes: Int64?
    var folder: String?
    var manageURL: String
    var id: String { name }
}

struct StorageMath: Sendable {
    var space: DiskSpace?
    var safeBytes: Int64
    var reviewBytes: Int64
    var icloudLocalBytes: Int64?
}

struct SpeedTest: Sendable {
    var mbps: Double
    var latencyMs: Double?
    var bytes: Int
    var seconds: Double
    var when: Date
}

struct HardwareInfo: Sendable {
    var model: String
    var identifier: String
    var chip: String
    var memoryGB: Int
    var appleSilicon: Bool
}

struct MacVerdict: Sendable {
    var level: Verdict
    var headline: String
    var reasons: [String]
    var cheapestFix: String
}

struct BuiltInAlternative: Identifiable, Sendable {
    var installedApp: String
    var path: String
    var builtIn: String
    var note: String
    var open: String?          // app path or URL scheme for the built-in thing
    var id: String { path }
}

struct BootTiming: Sendable {
    struct Item: Identifiable, Sendable {
        var name: String
        var secondsAfterLogin: Double
        var id: String { name }
    }
    var bootDate: Date?
    var loginDate: Date?
    var bootToLoginSeconds: Double?
    var loginToReadySeconds: Double?
    var items: [Item]
}

// MARK: - Gathering

enum MoneyInfo {

    // MARK: 1. Subscriptions

    /// Apps that are normally paid by subscription, how to recognise them, and where to manage the plan.
    static let subscriptionCatalog: [(match: [String], vendor: String, manage: String, note: String)] = [
        (["com.adobe."], "Adobe Creative Cloud", "https://account.adobe.com/plans", "Photoshop, Lightroom, Acrobat and friends are monthly."),
        (["com.microsoft.word", "com.microsoft.excel", "com.microsoft.powerpoint", "com.microsoft.outlook", "com.microsoft.onenote"], "Microsoft 365", "https://account.microsoft.com/services", "Office is a yearly plan unless you bought a one-time copy."),
        (["com.getdropbox."], "Dropbox", "https://www.dropbox.com/account/plan", "Free below 2 GB; the Plus plan is monthly."),
        (["com.google.drivefs"], "Google One", "https://one.google.com/storage", "Google Drive storage above 15 GB is a Google One plan."),
        (["com.microsoft.onedrive"], "Microsoft OneDrive", "https://account.microsoft.com/services", "Usually bundled with Microsoft 365."),
        (["com.setapp."], "Setapp", "https://my.setapp.com", "A monthly bundle of apps."),
        (["com.nordvpn."], "NordVPN", "https://my.nordaccount.com", "VPN subscription."),
        (["com.expressvpn."], "ExpressVPN", "https://www.expressvpn.com/subscriptions", "VPN subscription."),
        (["com.surfshark."], "Surfshark", "https://my.surfshark.com", "VPN subscription."),
        (["com.norton.", "com.symantec."], "Norton", "https://my.norton.com", "Antivirus subscription. macOS has built-in protection; see the alternatives card."),
        (["com.mcafee."], "McAfee", "https://home.mcafee.com", "Antivirus subscription. macOS has built-in protection; see the alternatives card."),
        (["com.avast.", "com.avg."], "Avast / AVG", "https://my.avast.com", "Antivirus subscription."),
        (["com.kaspersky."], "Kaspersky", "https://my.kaspersky.com", "Antivirus subscription."),
        (["com.macpaw.cleanmymac", "com.macpaw.CleanMyMac"], "CleanMyMac", "https://my.macpaw.com", "Cleaner subscription. Tidy for Mac does this for free."),
        (["com.kromtech.", "com.mackeeper."], "MacKeeper", "https://account.mackeeper.com", "Cleaner subscription. Tidy for Mac does this for free."),
        (["com.spotify."], "Spotify", "https://www.spotify.com/account/subscription/", "Music subscription."),
        (["com.evernote."], "Evernote", "https://www.evernote.com/Settings.action", "Notes subscription; Apple Notes is free."),
        (["notion.id", "com.notion."], "Notion", "https://www.notion.so/my-account", "Free tier is generous; check if you're on a paid plan."),
        (["com.grammarly."], "Grammarly", "https://account.grammarly.com/subscription", "Premium is a subscription; the free tier and macOS spell-check cover most people."),
        (["com.agilebits.onepassword", "com.1password."], "1Password", "https://my.1password.com", "Password manager subscription; macOS Passwords is free on recent versions."),
        (["com.backblaze."], "Backblaze", "https://secure.backblaze.com/account_billing.htm", "Cloud backup subscription. Keep it if it's your only backup."),
        (["com.carbonite."], "Carbonite", "https://account.carbonite.com", "Cloud backup subscription."),
        (["com.parallels."], "Parallels Desktop", "https://my.parallels.com", "Yearly subscription for running Windows."),
        (["us.zoom.xos"], "Zoom", "https://zoom.us/billing", "Free for most home use; check you're not on Pro by accident."),
        (["com.headspace.", "com.calm."], "Headspace / Calm", "https://apps.apple.com/account/subscriptions", "Wellness subscription."),
        (["com.duolingo."], "Duolingo", "https://apps.apple.com/account/subscriptions", "Super Duolingo is a subscription; the free tier works."),
        (["com.tinyspeck.slackmacgap"], "Slack", "https://slack.com/admin/billing", "Paid per workspace; free tier keeps 90 days of history."),
        (["com.todesktop.230313mzl4w4u92", "com.openai."], "ChatGPT", "https://chatgpt.com/#settings/Subscription", "Plus is monthly; the free tier covers most home use."),
        (["com.anthropic.claudefordesktop"], "Claude", "https://claude.ai/settings/billing", "Pro is monthly; the free tier exists."),
    ]

    static func subscriptions() -> [SubscriptionApp] {
        var out: [SubscriptionApp] = []
        for u in Scanner.contents(URL(fileURLWithPath: "/Applications")) where u.pathExtension == "app" {
            guard let bid = Bundle(url: u)?.bundleIdentifier?.lowercased() else { continue }
            let name = u.deletingPathExtension().lastPathComponent
            for entry in subscriptionCatalog where entry.match.contains(where: { bid.hasPrefix($0.lowercased()) || name.lowercased().contains($0.lowercased()) }) {
                out.append(SubscriptionApp(name: name, path: u.path, vendor: entry.vendor, lastUsed: Scanner.lastUsed(u), manageURL: entry.manage, note: entry.note))
                break
            }
        }
        // One row per vendor, keeping the most recently used app as its representative.
        var byVendor: [String: SubscriptionApp] = [:]
        for s in out {
            if let e = byVendor[s.vendor], (e.lastUsed ?? .distantPast) >= (s.lastUsed ?? .distantPast) { continue }
            byVendor[s.vendor] = s
        }
        return byVendor.values.sorted { ($0.daysIdle ?? 9999) > ($1.daysIdle ?? 9999) }
    }

    // MARK: 2. Cloud drives

    static func cloudDrives() -> [CloudDrive] {
        let running = Scanner.runningBundleIDs
        let procs = SystemInfo.processes()
        let birdRunning = procs.contains { URL(fileURLWithPath: $0.command).lastPathComponent == "bird" }
        let cs = Scanner.library.appendingPathComponent("CloudStorage")
        func csFolder(_ prefix: String) -> URL? { Scanner.contents(cs).first { $0.lastPathComponent.hasPrefix(prefix) } }
        var out: [CloudDrive] = []
        // The iCloud Drive folder isn't readable without Full Disk Access, so "installed" also
        // counts the sync daemon being alive; sizes are only shown when the folder can be read.
        let icloud = Scanner.library.appendingPathComponent("Mobile Documents")
        let icloudReadable = (try? FileManager.default.contentsOfDirectory(atPath: icloud.path)) != nil
        let icloudInstalled = icloudReadable || birdRunning
        out.append(CloudDrive(name: "iCloud Drive", installed: icloudInstalled, running: birdRunning,
                              localBytes: icloudReadable ? Scanner.size(of: icloud) : nil, folder: icloudReadable ? icloud.path : nil,
                              manageURL: "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings:icloud"))
        let defs: [(String, String, String, String)] = [
            ("Dropbox", "com.getdropbox.dropbox", "Dropbox", "https://www.dropbox.com/account/plan"),
            ("Google Drive", "com.google.drivefs", "GoogleDrive", "https://one.google.com/storage"),
            ("OneDrive", "com.microsoft.OneDrive", "OneDrive", "https://account.microsoft.com/services"),
            ("Box", "com.box.desktop", "Box", "https://app.box.com/account"),
        ]
        for (name, bid, prefix, url) in defs {
            let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) != nil
            let folder = csFolder(prefix) ?? (name == "Dropbox" ? (FileManager.default.fileExists(atPath: Scanner.home.appendingPathComponent("Dropbox").path) ? Scanner.home.appendingPathComponent("Dropbox") : nil) : nil)
            guard app || folder != nil else { continue }
            out.append(CloudDrive(name: name, installed: true, running: running.contains(bid),
                                  localBytes: folder.map { Scanner.size(of: $0) }, folder: folder?.path, manageURL: url))
        }
        return out
    }

    // MARK: 3. Storage math

    static func storageMath() -> StorageMath {
        let safeKinds: [CleanKind] = [.caches, .logs, .installers, .devCaches, .claude]
        let reviewKinds: [CleanKind] = [.leftovers, .iosBackups, .bigFiles, .unusedApps]
        var safe: Int64 = 0, review: Int64 = 0
        for k in safeKinds { safe += Scanner.scan(k).selectedTotal }
        for k in reviewKinds { review += Scanner.scan(k).items.filter { !$0.isProtected }.reduce(0) { $0 + $1.size } }
        let icloud = Scanner.library.appendingPathComponent("Mobile Documents")
        let ic = FileManager.default.fileExists(atPath: icloud.path) ? Scanner.size(of: icloud) : nil
        return StorageMath(space: DiskSpace.current(), safeBytes: safe, reviewBytes: review, icloudLocalBytes: ic)
    }

    /// Typical prices, US, 2026. Shown as "about" and dated in the UI. Edit here when they change.
    static let icloudTiers: [(gb: Int, usdPerMonth: Double)] = [(50, 0.99), (200, 2.99), (2000, 9.99), (6000, 29.99), (12000, 59.99)]
    static let externalSSDPerTB = 70.0

    // MARK: 4. Internet speed test

    /// Downloads from Cloudflare's speed-test endpoint and times it. Two passes: a small one to warm
    /// up and measure latency, then a size chosen so the real pass lasts a few seconds.
    static func speedTest() -> SpeedTest? {
        func fetch(_ bytes: Int, timeout: TimeInterval) -> (Int, TimeInterval)? {
            guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=\(bytes)") else { return nil }
            let sem = DispatchSemaphore(value: 0)
            var got: Int?
            let t0 = Date()
            var req = URLRequest(url: url, timeoutInterval: timeout)
            req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            let cfg = URLSessionConfiguration.ephemeral
            cfg.urlCache = nil
            URLSession(configuration: cfg).dataTask(with: req) { d, _, _ in got = d?.count; sem.signal() }.resume()
            _ = sem.wait(timeout: .now() + timeout + 2)
            guard let n = got, n > 0 else { return nil }
            return (n, Date().timeIntervalSince(t0))
        }
        guard let warm = fetch(1_000_000, timeout: 10) else { return nil }
        let latency = fetch(0, timeout: 5).map { $0.1 * 1000 }
        let warmMbps = Double(warm.0) * 8 / warm.1 / 1_000_000
        // Aim for about 4 seconds of download, capped at 200 MB.
        let target = min(200_000_000, max(10_000_000, Int(warmMbps * 1_000_000 / 8 * 4)))
        guard let real = fetch(target, timeout: 30) else { return nil }
        return SpeedTest(mbps: Double(real.0) * 8 / real.1 / 1_000_000, latencyMs: latency, bytes: real.0, seconds: real.1, when: Date())
    }

    // MARK: 5 & 6. Hardware and the verdicts

    static func hardware() -> HardwareInfo {
        let json = SystemInfo.run("/usr/sbin/system_profiler", ["SPHardwareDataType", "-json"], timeout: 20)
        var hw = HardwareInfo(model: "Mac", identifier: "", chip: "", memoryGB: Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824), appleSilicon: Capabilities.isAppleSilicon)
        if let d = json.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let item = (o["SPHardwareDataType"] as? [[String: Any]])?.first {
            hw.model = item["machine_name"] as? String ?? hw.model
            hw.identifier = item["machine_model"] as? String ?? ""
            hw.chip = item["chip_type"] as? String ?? item["cpu_type"] as? String ?? ""
            if let m = item["physical_memory"] as? String, let n = Int(m.filter(\.isNumber)) { hw.memoryGB = n }
        }
        return hw
    }

    static func batteryDecision(_ b: BatteryInfo?) -> (level: Verdict, text: String)? {
        guard let b, let pct = b.healthPercent else { return nil }
        let cycles = b.cycles ?? 0
        let service = (b.condition ?? "").lowercased().contains("service")
        if service || pct < 80 {
            return (.act, String(localized: "At \(pct)% of its original capacity\(service ? ", and macOS itself says service is recommended" : ""), this battery is below Apple's 80% service threshold. A replacement is a fair buy now. Typical Apple price in the US in 2026 is about $130 to $250 depending on the model; check Apple's page for yours."))
        }
        if pct < 85 || cycles > 800 {
            return (.watch, String(localized: "\(pct)% at \(cycles) cycles. Normal wear, getting toward the end. No need to spend anything yet; when it drops under 80%, Apple's threshold, a replacement makes sense. Apple laptops are rated for 1,000 cycles."))
        }
        return (.good, String(localized: "\(pct)% at \(cycles) cycles is healthy. If a shop suggests a new battery, the answer is no. Apple laptops are rated for 1,000 cycles and Apple's service threshold is 80%."))
    }

    static func macVerdict(hw: HardwareInfo, health: HealthReport?, memory: MemoryInfo?, space: DiskSpace?) -> MacVerdict {
        var reasons: [String] = []
        var score = 0    // higher is worse
        var fixes: [String] = []
        if hw.appleSilicon {
            reasons.append(String(localized: "\(hw.chip) is current-generation hardware. Apple supports these for many years of macOS updates."))
        } else {
            score += 2
            reasons.append(String(localized: "Intel Mac. Apple has said macOS 26 is the last version for Intel, so security updates continue for a while but new features won't."))
        }
        if let m = memory {
            if m.pressure >= 4 { score += 2; reasons.append(String(localized: "Memory is critical right now. With \(hw.memoryGB) GB, this Mac is short of memory for what you run.")); fixes.append(String(localized: "quit apps you're not using, or use fewer browser tabs")) }
            else if m.pressure >= 2 { score += 1; reasons.append(String(localized: "Memory is under pressure. \(hw.memoryGB) GB is on the low side for how you use it.")) }
            else { reasons.append(String(localized: "\(hw.memoryGB) GB of memory is enough for what you're running.")) }
        }
        if let s = space {
            let freeFrac = 1 - s.usedFraction
            if freeFrac < 0.1 { score += 1; reasons.append(String(localized: "The disk is nearly full, which makes any Mac feel old.")); fixes.append(String(localized: "run Tidy Up, then move big files to an external SSD (about $\(Int(externalSSDPerTB)) per TB)")) }
        }
        if let h = health {
            if let l = h.cpuSpeedLimit, l < 80 { score += 1; reasons.append(String(localized: "The chip is being slowed to stay cool. Dust in the vents or a stuck process, not age.")); fixes.append(String(localized: "clean the vents and check what's busy on the Speed tab")) }
            if let b = h.battery, let p = b.healthPercent, p < 80 { score += 1; reasons.append(String(localized: "The battery is worn (\(p)%). A new battery is far cheaper than a new Mac.")); fixes.append(String(localized: "battery service")) }
        }
        let level: Verdict = score >= 4 ? .act : (score >= 2 ? .watch : .good)
        let headline: String
        switch level {
        case .good:  headline = String(localized: "This Mac is fine. Don't replace it.")
        case .watch: headline = String(localized: "This Mac has years left with one cheap fix.")
        case .act:   headline = String(localized: "This Mac is holding you back. Start planning a replacement.")
        }
        let fix = fixes.first.map { String(localized: "Cheapest fix: \($0).") } ?? String(localized: "Nothing to buy.")
        return MacVerdict(level: level, headline: headline, reasons: reasons, cheapestFix: fix)
    }

    // MARK: 7. Built-in alternatives

    static let alternativesCatalog: [(match: [String], builtIn: String, note: String, open: String?)] = [
        (["com.adobe.acrobat", "com.readdle.pdfexpert", "com.smileonmymac.pdfpenpro", "com.pdfexpert"], "Preview", "Preview fills forms, signs, rotates, merges, and annotates PDFs for free.", "/System/Applications/Preview.app"),
        (["com.macpaw.cleanmymac", "com.kromtech", "com.mackeeper", "com.piriform.ccleaner", "com.nektony"], "Tidy for Mac", "You're looking at it. Same job, free, and it never deletes.", nil),
        (["com.norton", "com.symantec", "com.mcafee", "com.avast", "com.avg", "com.kaspersky", "com.bitdefender", "com.intego"], "macOS built-in protection", "XProtect, Gatekeeper, and notarization are on by default. Most home users don't need a paid antivirus; keep one only if work or school requires it.", nil),
        (["com.microsoft.word"], "Pages, or Google Docs", "Pages is free and opens Word files. If you only need occasional documents, that's enough.", "/Applications/Pages.app"),
        (["com.microsoft.excel"], "Numbers, or Google Sheets", "Numbers is free and opens Excel files. Heavy spreadsheet users may still want Excel.", "/Applications/Numbers.app"),
        (["com.microsoft.powerpoint"], "Keynote, or Google Slides", "Keynote is free and opens PowerPoint files.", "/Applications/Keynote.app"),
        (["com.evernote", "notion.id"], "Notes", "Apple Notes syncs, scans documents, and searches handwriting, free.", "/System/Applications/Notes.app"),
        (["com.agilebits.onepassword", "com.1password", "com.lastpass", "com.dashlane", "com.bitwarden"], "Passwords", "macOS 15 and later has a full Passwords app with sharing and two-factor codes.", "/System/Applications/Passwords.app"),
        (["com.techsmith.snagit", "com.telestream.screenflow", "com.getcleanshot"], "Screenshot (⇧⌘5)", "The built-in Screenshot tool records the screen and captures windows.", nil),
        (["com.macitbetter.betterzip", "com.winzip", "com.stuffit"], "Archive Utility", "Double-click a zip. That's it. Compress with right-click.", nil),
        (["com.grammarly"], "Spelling and grammar in macOS", "Edit > Spelling and Grammar is built into every text field.", nil),
        (["com.apple.iWork"], "", "", nil),
    ]

    static func builtInAlternatives() -> [BuiltInAlternative] {
        var out: [BuiltInAlternative] = []
        for u in Scanner.contents(URL(fileURLWithPath: "/Applications")) where u.pathExtension == "app" {
            guard let bid = Bundle(url: u)?.bundleIdentifier?.lowercased() else { continue }
            if bid == "com.keithadler.tidymac" { continue }
            for a in alternativesCatalog where !a.builtIn.isEmpty && a.match.contains(where: { bid.hasPrefix($0) }) {
                let open = a.open.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }
                out.append(BuiltInAlternative(installedApp: u.deletingPathExtension().lastPathComponent, path: u.path, builtIn: a.builtIn, note: a.note, open: open))
                break
            }
        }
        return out
    }

    // MARK: 9. Boot timing

    static func bootTiming(_ procs: [ProcInfo], loginItems: [LoginItem], agents: [AgentInfo]) -> BootTiming {
        var t = BootTiming(bootDate: nil, loginDate: nil, bootToLoginSeconds: nil, loginToReadySeconds: nil, items: [])
        // kern.boottime is a timeval
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        if sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0 { t.bootDate = Date(timeIntervalSince1970: TimeInterval(tv.tv_sec)) }
        // Login time from `last`: "sam  console  Wed Sep  2 07:36   still logged in"
        let last = SystemInfo.run("/usr/bin/last", ["-1", NSUserName()], timeout: 5)
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "EEE MMM d HH:mm yyyy"
        if let line = last.split(separator: "\n").first(where: { $0.contains("console") }),
           let m = line.range(of: #"[A-Z][a-z]{2} [A-Z][a-z]{2} +\d{1,2} \d{2}:\d{2}"#, options: .regularExpression) {
            let stamp = line[m].replacingOccurrences(of: "  ", with: " ")
            let year = Calendar.current.component(.year, from: Date())
            t.loginDate = f.date(from: "\(stamp) \(year)")
        }
        if let b = t.bootDate, let l = t.loginDate, l > b { t.bootToLoginSeconds = l.timeIntervalSince(b) }
        // Start times of login items and helpers, relative to login.
        let ps = SystemInfo.run("/bin/ps", ["-axo", "lstart=,comm="], timeout: 10)
        let lf = DateFormatter(); lf.locale = Locale(identifier: "en_US_POSIX"); lf.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        var items: [BootTiming.Item] = []
        if let login = t.loginDate {
            let targets: [(String, String)] = loginItems.map { ($0.name, $0.path) } + agents.filter { !$0.system && !$0.program.isEmpty }.map { ($0.vendor, $0.program) }
            for line in ps.split(separator: "\n") {
                let s = line.trimmingCharacters(in: .whitespaces)
                guard s.count > 25 else { continue }
                let stampRaw = String(s.prefix(24)).replacingOccurrences(of: "  ", with: " ")
                let comm = String(s.dropFirst(24)).trimmingCharacters(in: .whitespaces)
                guard let start = lf.date(from: stampRaw) else { continue }
                for (name, path) in targets where comm.hasPrefix(path) {
                    let delta = start.timeIntervalSince(login)
                    if delta >= 0 && delta < 600 && !items.contains(where: { $0.name == name }) {
                        items.append(BootTiming.Item(name: name, secondsAfterLogin: delta))
                    }
                }
            }
            if let ready = items.map(\.secondsAfterLogin).max() { t.loginToReadySeconds = ready }
        }
        t.items = items.sorted { $0.secondsAfterLogin > $1.secondsAfterLogin }
        return t
    }
}
