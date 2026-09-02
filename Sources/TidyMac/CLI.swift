//  The command-line face of Tidy for Mac.
//
//  The same binary that runs the app also answers to `tidymac <command>` (installed as a symlink in
//  /usr/local/bin or Homebrew's bin, whichever is writable). Every command reuses the scanners and actions the windows use, so the two can
//  never disagree. Commands run before SwiftUI starts and exit; the GUI never appears.
//
//  Exit codes: 0 ok (or green verdict), 1 yellow verdict, 2 red verdict, 3 needs confirmation,
//  64 usage error, 70 something failed.

import Foundation
import AppKit

enum CLI {

    /// When launched through the `tidymac` symlink, Bundle.main doesn't know about the .app, so
    /// resolve the real executable path and read the enclosing bundle's Info.plist directly.
    static let version: String = {
        if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String { return v }
        // Bundle.main.executableURL is absolute even when argv[0] is a bare name found on the PATH.
        var url = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
        while url.path != "/" {
            if url.pathExtension == "app", let b = Bundle(url: url), let v = b.infoDictionary?["CFBundleShortVersionString"] as? String { return v }
            url = url.deletingLastPathComponent()
        }
        return "dev"
    }()

    static let usage = """
    tidymac — a friendly, safe cleanup and speed-up for your Mac (command-line face)

    USAGE
      tidymac scan [--card <name>…] [--json]
      tidymac up (--safe | --card <name>… | --all-checked) [--dry-run] [--yes] [--json]
      tidymac speed [--card <name>…] [--all] [--updates] [--app-updates] [--bench] [--json]
      tidymac receipts [--json]
      tidymac restore <session-id | last> [--json]
      tidymac trash [--empty --yes] [--json]
      tidymac disk [--json]
      tidymac money [--speedtest] [--plan <mbps>] [--json]
      tidymac sort [--desktop] [--downloads] [--older-than <days>] [--dry-run] [--yes] [--json]
      tidymac report [--out <file>] [--md] [--open]
      tidymac screenshots <directory>
      tidymac help | version

    COMMANDS
      scan        Show what could be tidied, card by card. Nothing is changed.
      up          Move the pre-checked items of the chosen cards to the Trash and save a receipt.
                  --safe is the same set the weekly quiet tidy uses (caches, logs, installers,
                  developer caches). Asks first unless --yes; --dry-run only shows the plan.
      speed       Health verdict and the Speed cards. Exit code is 0 green, 1 yellow, 2 red.
      receipts    Every past session, newest first, with its id.
      restore     Put a session's items back where they were (only while they are in the Trash).
      trash       Size of the Trash; --empty --yes asks Finder to empty it.
      disk        The boot disk map: disk → partition → container → volume → snapshot.
      money       Subscriptions that look unused, cloud-drive overlap, storage math, the battery
                  and "is this Mac done" verdicts, built-in alternatives. --speedtest downloads
                  from a nearby server for a few seconds; --plan compares with your bill.
      sort        File loose Desktop/Downloads files older than N days (default 7) into typed
                  folders in a "Tidied" folder. Moves, never deletes; receipt saved; --dry-run
                  shows the plan. Both folders unless you name one.
      report      The monthly checkup as one page. HTML by default, --md for Markdown, --out to
                  choose the file (default ~/Desktop/Tidy checkup <date>.html), --open to view it.
      screenshots Render every window with sample data into PNGs (used for the README).

    SCAN / UP CARDS
      caches logs installers dev claude duplicates leftovers unused backups big

    SPEED CARDS
      health now startup browsers wifi sync timemachine rosetta menubar printers power
      sleep safety batteries defaults    slow, on request: updates app-updates bench

    OPTIONS
      --json      Machine-readable output. Sizes are bytes.
      --yes       Skip the confirmation for up and trash --empty.
      --dry-run   Show what up would move, move nothing.

    Nothing is ever deleted outright: everything goes to the Trash, and every action is recorded in
    a receipt you can undo with `tidymac restore`. See docs/CLI.md for details and examples.
    """

    // MARK: Entry

    /// Called before SwiftUI starts. Returns normally (GUI launches) unless a command was given.
    static func runIfRequested() {
        var args = Array(CommandLine.arguments.dropFirst())
        // Legacy flags from earlier builds.
        switch args.first {
        case "--scan":  args = ["scan"] + args.dropFirst()
        case "--speed": args = ["speed", "--all"] + args.dropFirst().map { $0 == "--appupdates" ? "--app-updates" : $0 }
        case "--dump":  args = ["disk"]
        default: break
        }
        guard let cmd = args.first else { return }
        let opts = Options(Array(args.dropFirst()))
        let code: Int32
        switch cmd {
        case "help", "--help", "-h": print(usage); code = 0
        case "version", "--version", "-v": print("tidymac \(version) (Tidy for Mac)"); code = 0
        case "scan": code = scan(opts)
        case "up": code = up(opts)
        case "speed": code = speed(opts)
        case "receipts": code = receipts(opts)
        case "restore": code = restore(opts)
        case "trash": code = trash(opts)
        case "disk": code = disk(opts)
        case "money": code = money(opts)
        case "sort": code = sort(opts)
        case "report": code = report(opts)
        case "--screenshots", "screenshots": return   // handled by AppDelegate once AppKit is up
        default:
            if cmd.hasPrefix("-") { return }           // unknown flag (e.g. from LaunchServices): launch the GUI
            fputs("tidymac: unknown command '\(cmd)'\n\n\(usage)\n", stderr); code = 64
        }
        exit(code)
    }

    struct Options {
        var flags = Set<String>()
        var cards: [String] = []
        var positional: [String] = []
        var values: [String: String] = [:]   // --plan 300, --older-than 30, --out file
        static let valued: Set<String> = ["--plan", "--older-than", "--out"]
        init(_ args: [String]) {
            var i = 0
            while i < args.count {
                let a = args[i]
                if a == "--card", i + 1 < args.count { cards.append(args[i + 1]); i += 2; continue }
                if a.hasPrefix("--card=") { cards.append(String(a.dropFirst(7))); i += 1; continue }
                if Options.valued.contains(a), i + 1 < args.count { values[a] = args[i + 1]; i += 2; continue }
                if let eq = a.firstIndex(of: "="), Options.valued.contains(String(a[..<eq])) { values[String(a[..<eq])] = String(a[a.index(after: eq)...]); i += 1; continue }
                if a.hasPrefix("-") { flags.insert(a) } else { positional.append(a) }
                i += 1
            }
        }
        var json: Bool { flags.contains("--json") }
        var yes: Bool { flags.contains("--yes") || flags.contains("-y") }
    }

    // MARK: Output helpers

    static func emit(_ obj: Any) {
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
           let s = String(data: data, encoding: .utf8) { print(s) }
    }

    static func iso(_ d: Date?) -> String? {
        guard let d else { return nil }
        return ISO8601DateFormatter().string(from: d)
    }

    static func pad(_ s: String, _ n: Int) -> String { s.count >= n ? s : s + String(repeating: " ", count: n - s.count) }

    static func fail(_ msg: String, json: Bool) -> Int32 {
        if json { emit(["error": msg]) } else { fputs("tidymac: \(msg)\n", stderr) }
        return 70
    }

    static var isTTY: Bool { isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1 }

    static func confirm(_ question: String) -> Bool {
        print("\(question) [y/N] ", terminator: "")
        guard let line = readLine() else { return false }
        return ["y", "yes"].contains(line.trimmingCharacters(in: .whitespaces).lowercased())
    }

    // MARK: Card names

    static let scanAliases: [String: CleanKind] = [
        "caches": .caches, "logs": .logs, "installers": .installers, "dev": .devCaches, "devcaches": .devCaches,
        "claude": .claude, "duplicates": .duplicates, "dupes": .duplicates, "leftovers": .leftovers,
        "unused": .unusedApps, "apps": .unusedApps, "backups": .iosBackups, "big": .bigFiles, "bigfiles": .bigFiles,
    ]

    static func scanKinds(_ opts: Options) -> [CleanKind]? {
        if opts.cards.isEmpty { return CleanKind.allCases }
        var out: [CleanKind] = []
        for c in opts.cards {
            guard let k = scanAliases[c.lowercased()] ?? CleanKind(rawValue: c) else {
                fputs("tidymac: unknown card '\(c)'. Cards: \(scanAliases.keys.sorted().joined(separator: " "))\n", stderr)
                return nil
            }
            if !out.contains(k) { out.append(k) }
        }
        return out
    }

    static func categoryJSON(_ c: CleanCategory) -> [String: Any] {
        ["kind": c.kind.rawValue, "title": c.kind.title, "safety": c.kind.safety.label, "bytes": c.total,
         "checkedBytes": c.selectedTotal, "items": c.items.map { i -> [String: Any] in
            var d: [String: Any] = ["name": i.name, "detail": i.detail, "bytes": i.size, "checked": i.selected, "paths": i.paths, "why": i.why]
            if let p = i.protectedBy { d["protected"] = p }
            if let k = i.keeperPath { d["kept"] = k }
            return d
        }]
    }

    // MARK: scan

    static func scan(_ opts: Options) -> Int32 {
        guard let kinds = scanKinds(opts) else { return 64 }
        let space = DiskSpace.current()
        let trash = Scanner.trashState()
        let cats = kinds.map { Scanner.scan($0) }.filter { !$0.items.isEmpty }
        if opts.json {
            var out: [String: Any] = ["categories": cats.map(categoryJSON), "checkedBytes": cats.reduce(0) { $0 + $1.selectedTotal }]
            if let s = space { out["disk"] = ["totalBytes": s.total, "freeBytes": s.free, "usedFraction": s.usedFraction] }
            out["trash"] = ["readable": trash.readable, "bytes": trash.size, "items": trash.count]
            emit(out)
            return 0
        }
        if let s = space { print("Disk: \(Bytes.string(s.free)) free of \(Bytes.string(s.total)) (\(Int(s.usedFraction * 100))% full)") }
        print("Trash: \(trash.readable ? "\(trash.count) items, \(Bytes.string(trash.size))" : "not readable without Full Disk Access")")
        print()
        if cats.isEmpty { print("Sparkling clean. Nothing to tidy."); return 0 }
        for c in cats {
            print("== \(c.kind.title)  [\(c.kind.safety.label)]  \(Bytes.string(c.total)) in \(c.items.count) items, \(c.selectedCount) pre-checked")
            for i in c.items {
                let mark = i.isProtected ? "🛡" : (i.selected ? "x" : " ")
                print("   [\(mark)] \(pad(Bytes.string(i.size), 10)) \(i.name)  — \(i.detail)\(i.paths.count > 1 ? "  (\(i.paths.count) places)" : "")")
            }
            print()
        }
        let checked = cats.reduce(0) { $0 + $1.selectedTotal }
        print("Pre-checked: \(Bytes.string(checked)), \(Bytes.friendly(checked)). Run `tidymac up --safe` (or --card …) to move them to the Trash.")
        return 0
    }

    // MARK: up

    static func up(_ opts: Options) -> Int32 {
        let kinds: [CleanKind]
        if opts.flags.contains("--safe") { kinds = CleanKind.quiet }
        else if opts.flags.contains("--all-checked") { kinds = CleanKind.allCases }
        else if !opts.cards.isEmpty { guard let k = scanKinds(opts) else { return 64 }; kinds = k }
        else {
            fputs("tidymac up: say what to tidy: --safe, --card <name>…, or --all-checked. Nothing was changed.\n", stderr)
            return 64
        }
        let cats = kinds.map { Scanner.scan($0) }
        let items = cats.flatMap { $0.items.filter { $0.selected && !$0.isProtected } }
        let total = items.reduce(0) { $0 + $1.size }
        let plan: [[String: Any]] = items.map { ["name": $0.name, "bytes": $0.size, "paths": $0.paths] }
        if items.isEmpty {
            if opts.json { emit(["moved": 0, "bytes": 0, "message": "nothing pre-checked in those cards"]) }
            else { print("Nothing pre-checked in those cards. Nothing was changed.") }
            return 0
        }
        if opts.flags.contains("--dry-run") {
            if opts.json { emit(["dryRun": true, "wouldMove": plan, "bytes": total]) }
            else {
                print("Would move \(items.count) items (\(Bytes.string(total))) to the Trash:")
                for i in items { print("   \(pad(Bytes.string(i.size), 10)) \(i.name)") }
                print("Nothing was changed (dry run).")
            }
            return 0
        }
        if !opts.yes {
            if isTTY {
                print("Move \(items.count) items (\(Bytes.string(total)), \(Bytes.friendly(total))) to the Trash?")
                for i in items.prefix(15) { print("   \(pad(Bytes.string(i.size), 10)) \(i.name)") }
                if items.count > 15 { print("   … and \(items.count - 15) more") }
                if !confirm("Continue?") { print("Nothing was changed."); return 3 }
            } else {
                if opts.json { emit(["needsConfirmation": true, "wouldMove": plan, "bytes": total, "hint": "re-run with --yes"]) }
                else { print("Would move \(items.count) items (\(Bytes.string(total))). Re-run with --yes to do it, or --dry-run to see the list. Nothing was changed.") }
                return 3
            }
        }
        var records: [TidyRecord] = []
        let kindOf = Dictionary(uniqueKeysWithValues: cats.flatMap { c in c.items.map { ($0.id, c.kind) } })
        for i in items {
            let per = i.size / Int64(max(i.paths.count, 1))
            for p in i.paths {
                let t = Scanner.moveToTrash(p)
                records.append(TidyRecord(id: UUID(), name: i.name, originalPath: p, trashPath: t, size: per, restored: false, kind: kindOf[i.id]))
            }
        }
        let session = TidySession(id: UUID(), date: Date(), automatic: false, label: "tidymac up (command line)", records: records)
        MainActor.assumeIsolated { History.shared.add(session) }
        if opts.json {
            emit(["session": session.id.uuidString, "moved": session.movedCount, "failed": session.failedCount, "bytes": session.totalSize])
        } else {
            print("Moved \(session.movedCount) items (\(Bytes.string(session.totalSize))) to the Trash.\(session.failedCount > 0 ? " \(session.failedCount) couldn't be moved (macOS protects them)." : "")")
            print("Receipt \(String(session.id.uuidString.prefix(8))) saved. `tidymac restore last` puts everything back while it's still in the Trash.")
        }
        return session.failedCount > 0 && session.movedCount == 0 ? 70 : 0
    }

    // MARK: speed

    static let speedCards = ["health", "now", "startup", "browsers", "wifi", "sync", "timemachine", "rosetta", "menubar",
                             "printers", "power", "sleep", "safety", "batteries", "defaults", "updates", "app-updates", "bench"]
    static let slowCards: Set<String> = ["updates", "app-updates", "bench"]

    static func speed(_ opts: Options) -> Int32 {
        var wanted: Set<String>
        if opts.cards.isEmpty {
            wanted = Set(speedCards).subtracting(slowCards)
            if !opts.flags.contains("--all") { wanted.remove("startup") }   // startup talks to System Events, which may prompt
        } else {
            wanted = Set(opts.cards.map { $0.lowercased() })
            if let bad = wanted.first(where: { !speedCards.contains($0) }) {
                fputs("tidymac speed: unknown card '\(bad)'. Cards: \(speedCards.joined(separator: " "))\n", stderr); return 64
            }
        }
        if opts.flags.contains("--all") { wanted.formUnion(Set(speedCards).subtracting(slowCards)) }
        if opts.flags.contains("--updates") { wanted.insert("updates") }
        if opts.flags.contains("--app-updates") { wanted.insert("app-updates") }
        if opts.flags.contains("--bench") { wanted.insert("bench") }
        let json = opts.json
        var out: [String: Any] = [:]

        // Gather on the main actor so the same SpeedModel verdict logic is reused.
        return MainActor.assumeIsolated { () -> Int32 in
            let m = SpeedModel()
            m.demo = true                     // no timers, no background refresh
            let procs = SystemInfo.processes()
            m.space = DiskSpace.current()
            m.memory = SystemInfo.memory()
            m.uptimeDays = SystemInfo.uptimeDays
            m.apps = SystemInfo.appLoads(procs)
            m.background = SystemInfo.backgroundActivity(procs)
            if wanted.contains("health") { m.health = SystemInfo.health() }
            if wanted.contains("startup") { m.agents = SystemInfo.agents(procs); let li = SystemInfo.loginItems(); m.loginItems = li.items; if li.denied { m.loginItemsError = "Automation permission declined" } }
            if wanted.contains("browsers") { m.browsers = SystemInfo.browsers() }
            if wanted.contains("wifi") { m.network = SystemInfo2.network() }
            if wanted.contains("sync") { m.sync = SystemInfo2.sync(procs, history: [:]) }
            if wanted.contains("timemachine") { m.timeMachine = SystemInfo2.timeMachine() }
            if wanted.contains("rosetta") { m.rosettaApps = SystemInfo2.rosettaApps() }
            if wanted.contains("menubar") { m.menuBarApps = SystemInfo2.menuBarApps(procs); m.widgets = SystemInfo2.widgets(procs) }
            if wanted.contains("printers") { m.printers = SystemInfo2.printers() }
            if wanted.contains("power") { m.power = SystemInfo2.power() }
            if wanted.contains("sleep") { m.sleep = SystemInfo2.sleep() }
            if wanted.contains("safety") { m.safety = SystemInfo3.safety() }
            if wanted.contains("batteries") { m.deviceBatteries = SystemInfo3.deviceBatteries() }
            if wanted.contains("defaults") { m.defaultApps = SystemInfo3.defaultApps() }
            if wanted.contains("updates") { m.updates = SystemInfo.pendingUpdates() }
            if wanted.contains("app-updates") { m.appUpdates = SystemInfo2.appUpdates() }
            var bench: [VolumeBench] = []
            if wanted.contains("bench") {
                for v in SystemInfo2.volumes() { var b = v; if let r = SystemInfo2.benchmark(v.path) { b.writeMBs = r.write; b.readMBs = r.read }; bench.append(b) }
            }

            let verdict = m.verdict
            let code: Int32 = verdict == .good ? 0 : (verdict == .watch ? 1 : 2)
            let verdictName = verdict == .good ? "green" : (verdict == .watch ? "yellow" : "red")

            if json {
                out["verdict"] = verdictName
                out["findings"] = m.findings.map { ["level": $0.level == .act ? "red" : "yellow", "title": $0.title, "detail": $0.detail] }
                var cards: [String: Any] = [:]
                if let s = m.space { cards["disk"] = ["totalBytes": s.total, "freeBytes": s.free] }
                if let mem = m.memory { cards["memory"] = ["totalBytes": mem.total, "usedBytes": mem.used, "pressure": mem.pressure, "label": mem.pressureLabel] }
                cards["now"] = ["uptimeDays": m.uptimeDays, "background": m.background as Any,
                                "apps": m.apps.filter(\.isApp).prefix(15).map { ["name": $0.name, "cpuPercent": $0.cpu, "memoryBytes": $0.memory, "processes": $0.processes] }]
                if let h = m.health { cards["health"] = ["thermal": h.thermal, "cpuSpeedLimit": h.cpuSpeedLimit as Any, "smartOK": h.smartOK as Any, "macOS": h.osVersion,
                                                          "battery": h.battery.map { ["cycles": $0.cycles as Any, "healthPercent": $0.healthPercent as Any, "condition": $0.condition as Any] } as Any] }
                if wanted.contains("startup") { cards["startup"] = ["loginItems": m.loginItems.map { ["name": $0.name, "path": $0.path] }, "error": m.loginItemsError as Any,
                                                                     "agents": m.agents.map { ["label": $0.label, "vendor": $0.vendor, "loaded": $0.loaded, "system": $0.system, "disabled": $0.disabledByTidy, "memoryBytes": $0.memory, "cpuPercent": $0.cpu] }] }
                if wanted.contains("browsers") { cards["browsers"] = m.browsers.map { b in ["name": b.name, "running": b.running, "siteDataBytes": b.total,
                                                                                            "profiles": b.profiles.map { ["name": $0.name, "bytes": $0.siteData] },
                                                                                            "extensions": b.extensions.map { ["name": $0.name, "bytes": $0.size, "profile": $0.profile] }] } }
                if let n = m.network { cards["wifi"] = ["ssid": n.ssid as Any, "band": n.band as Any, "channel": n.channel as Any, "signalDBm": n.signal as Any, "signal": n.signalLabel, "txRateMbps": n.txRate as Any,
                                                        "dnsMillis": n.dnsMillis as Any, "gateway": n.gateway as Any, "gatewayMillis": n.gatewayMillis as Any, "fasterBandAvailable": n.fasterBandAvailable] }
                if wanted.contains("sync") { cards["sync"] = m.sync.map { ["name": $0.name, "running": $0.running, "cpuPercent": $0.cpuNow] } }
                if let t = m.timeMachine { cards["timemachine"] = ["configured": t.configured, "destination": t.destination as Any, "lastBackup": iso(t.lastBackup) as Any, "localSnapshots": t.localSnapshots.count] }
                if let r = m.rosettaApps { cards["rosetta"] = r.map { ["name": $0.name, "path": $0.path] } }
                if wanted.contains("menubar") { cards["menubar"] = ["apps": m.menuBarApps.map { ["name": $0.name, "memoryBytes": $0.memory] }, "widgets": m.widgets.map { ["name": $0.name, "memoryBytes": $0.memory, "count": $0.processes] }] }
                if let p = m.printers { cards["printers"] = p.map { ["name": $0.name, "default": $0.isDefault, "state": $0.state, "jobs": $0.jobs, "reason": $0.reason as Any] } }
                if let p = m.power { cards["power"] = ["onBattery": p.onBattery as Any, "percent": p.percent as Any, "charging": p.charging as Any, "lowPowerMode": p.lowPowerMode as Any, "displaySleepMinutes": p.displaySleepMinutes as Any] }
                if let s = m.sleep { cards["sleep"] = ["keepingAwake": s.assertions.map { ["process": $0.process, "type": $0.type, "reason": $0.reason as Any] },
                                                       "recentWakes": s.recentWakes.map { ["when": $0.when, "reason": $0.reason, "friendly": $0.friendly] },
                                                       "wakeForNetwork": s.wakeForNetwork as Any, "powerNap": s.powerNap as Any, "proximityWake": s.proximityWake as Any] }
                if let s = m.safety { cards["safety"] = s.map { ["key": $0.key, "name": $0.name, "ok": $0.ok as Any, "detail": $0.detail] } }
                if let d = m.deviceBatteries { cards["batteries"] = d.map { ["name": $0.name, "kind": $0.kind, "levels": Dictionary(uniqueKeysWithValues: $0.levels.map { ($0.0.isEmpty ? "main" : $0.0.lowercased(), $0.1) })] } }
                if wanted.contains("defaults") { cards["defaults"] = m.defaultApps.map { ["for": $0.name, "app": $0.current as Any] } }
                if let u = m.updates { cards["updates"] = u }
                if let a = m.appUpdates { cards["appUpdates"] = a.map { ["name": $0.name, "installed": $0.installed, "latest": $0.latest as Any, "source": $0.source, "status": "\($0.status)"] } }
                if !bench.isEmpty { cards["bench"] = bench.map { ["volume": $0.name, "internal": $0.isInternal, "readMBs": $0.readMBs as Any, "writeMBs": $0.writeMBs as Any] } }
                out["cards"] = cards
                emit(out)
                return code
            }

            // Text
            let dot = verdict == .good ? "🟢" : (verdict == .watch ? "🟡" : "🔴")
            print("\(dot) \(verdictName.capitalized): \(verdict == .good ? "your Mac is in good shape" : (verdict == .watch ? "a few things worth a look" : "something needs attention"))")
            for f in m.findings { print("   • \(f.title) — \(f.detail)") }
            if let s = m.space, let mem = m.memory {
                print("\nFree space \(Bytes.string(s.free)) of \(Bytes.string(s.total)) · Memory \(Bytes.string(mem.used)) of \(Bytes.string(mem.total)) (\(mem.pressureLabel)) · Since restart \(m.uptimeDays < 1 ? "today" : "\(Int(m.uptimeDays)) days")")
            }
            if let h = m.health {
                print("Temperature \(h.thermal)\(h.cpuSpeedLimit.map { $0 < 100 ? " (\($0)% speed)" : "" } ?? "") · Drive \(h.smartOK.map { $0 ? "healthy" : "reports a problem" } ?? "not reported") · Battery \(h.battery.map { "\($0.healthPercent ?? 0)% · \($0.cycles ?? 0) cycles · \($0.condition ?? "")" } ?? "none")")
            }
            if let bg = m.background { print("Background: \(bg)") }
            print("\n== What's using your Mac")
            for a in m.apps.filter(\.isApp).prefix(8) { print("   \(pad(Bytes.string(a.memory), 10)) \(pad(String(format: "%4.0f%% CPU", a.cpu), 10)) \(a.name)") }
            if wanted.contains("safety"), let s = m.safety {
                print("\n== Safety check-up")
                for c in s { print("   [\(c.ok == true ? "ok" : (c.ok == false ? "!!" : "??"))] \(c.name) — \(c.detail)") }
            }
            if wanted.contains("startup") {
                print("\n== Startup")
                if let e = m.loginItemsError { print("   (\(e))") }
                for li in m.loginItems { print("   login item: \(li.name)") }
                for a in m.agents where !a.system { print("   helper: \(a.vendor) · \(a.label) · \(a.disabledByTidy ? "off" : (a.loaded ? "loaded" : "not running")) · \(Bytes.string(a.memory))") }
            }
            if wanted.contains("browsers") {
                for b in m.browsers { print("\n== \(b.name)\(b.running ? " (open)" : ""): \(Bytes.string(b.total)) site data · \(b.extensions.count) extensions") }
            }
            if let n = m.network {
                print("\n== Internet")
                print("   \(n.band ?? "not on Wi-Fi") · signal \(n.signalLabel)\(n.signal.map { " (\($0) dBm)" } ?? "") · DNS \(n.dnsMillis.map { "\($0) ms" } ?? "—") · router \(n.gatewayMillis.map { String(format: "%.0f ms", $0) } ?? "—")\(n.fasterBandAvailable ? " · 5 GHz available" : "")")
            }
            if wanted.contains("sync") { print("\n== Cloud sync"); for s in m.sync where s.running { print("   \(s.name): running · \(Int(s.cpuNow))% CPU") } }
            if let t = m.timeMachine { print("\n== Time Machine: \(t.configured ? "backing up to \(t.destination ?? "a drive") · last \(t.lastBackup.map { $0.formatted(.relative(presentation: .named)) } ?? "unknown") · \(t.localSnapshots.count) local snapshots" : "not set up")") }
            if let r = m.rosettaApps { print("\n== Intel-only apps: \(r.isEmpty ? "none" : r.map(\.name).joined(separator: ", "))") }
            if wanted.contains("menubar") { print("\n== Menu bar apps"); for a in m.menuBarApps { print("   \(a.name) · \(Bytes.string(a.memory))") }; for w in m.widgets { print("   widgets: \(w.name) · \(Bytes.string(w.memory))") } }
            if let p = m.printers, !p.isEmpty { print("\n== Printers"); for x in p { print("   \(x.name)\(x.isDefault ? " (default)" : "") · \(x.state)\(x.jobs > 0 ? " · \(x.jobs) jobs" : "")") } }
            if let p = m.power, p.percent != nil { print("\n== Battery: \(p.percent ?? 0)% · \(p.onBattery == true ? "on battery" : "plugged in") · Low Power Mode \(p.lowPowerMode == true ? "on" : "off")") }
            if let s = m.sleep {
                print("\n== Sleep and wake")
                for a in s.assertions { print("   awake: \(a.process) — \(a.reason ?? a.type)") }
                for w in s.recentWakes.prefix(5) { print("   wake:  \(w.when) · \(w.friendly)") }
                print("   wake for network \(s.wakeForNetwork == true ? "on" : "off") · Power Nap \(s.powerNap == true ? "on" : "off")")
            }
            if let d = m.deviceBatteries, !d.isEmpty { print("\n== Device batteries"); for x in d { print("   \(x.name): \(x.levels.map { "\($0.0.isEmpty ? "" : $0.0 + " ")\($0.1)%" }.joined(separator: ", "))") } }
            if wanted.contains("defaults") { print("\n== Default apps"); for s in m.defaultApps { print("   \(pad(s.name, 26)) \(s.current.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? "—")") } }
            if let u = m.updates { print("\n== macOS updates: \(u.isEmpty ? "up to date" : u.joined(separator: ", "))") }
            if let a = m.appUpdates {
                print("\n== App updates")
                for x in a where x.status == .outdated { print("   \(x.name): \(x.installed) → \(x.latest ?? "?")") }
                if !a.contains(where: { $0.status == .outdated }) { print("   everything we could check is current") }
            }
            for b in bench { print("\n== Drive speed: \(b.name) read \(Int(b.readMBs ?? 0)) MB/s · write \(Int(b.writeMBs ?? 0)) MB/s · \(b.verdict)") }
            return code
        }
    }

    // MARK: receipts / restore

    static func receipts(_ opts: Options) -> Int32 {
        MainActor.assumeIsolated {
            let sessions = History.shared.sessions
            if opts.json {
                emit(sessions.map { s in ["id": s.id.uuidString, "date": iso(s.date) as Any, "label": s.label ?? (s.automatic ? "quiet tidy" : "tidymac up"), "automatic": s.automatic,
                                          "moved": s.movedCount, "failed": s.failedCount, "bytes": s.totalSize, "restorable": s.restorableCount,
                                          "items": s.records.map { ["name": $0.name, "path": $0.originalPath, "bytes": $0.size, "moved": $0.moved, "restored": $0.restored] }] })
                return 0
            }
            if sessions.isEmpty { print("No receipts yet."); return 0 }
            for s in sessions {
                print("\(s.id.uuidString.prefix(8))  \(s.date.formatted(date: .abbreviated, time: .shortened))  \(pad(s.label ?? (s.automatic ? "quiet tidy" : "tidymac up"), 32)) \(s.movedCount) items · \(Bytes.string(s.totalSize))\(s.restorableCount > 0 ? " · \(s.restorableCount) can be put back" : "")")
            }
            print("\n`tidymac restore <id>` or `tidymac restore last` puts a session back while it's still in the Trash.")
            return 0
        }
    }

    static func restore(_ opts: Options) -> Int32 {
        guard let which = opts.positional.first else { fputs("tidymac restore: give a session id (see `tidymac receipts`) or `last`.\n", stderr); return 64 }
        return MainActor.assumeIsolated {
            let sessions = History.shared.sessions
            let session: TidySession?
            if which == "last" { session = sessions.first } else { session = sessions.first { $0.id.uuidString.lowercased().hasPrefix(which.lowercased()) } }
            guard let s = session else { return fail("no session matching '\(which)'", json: opts.json) }
            let r = History.shared.restoreAllSync(in: s)
            if opts.json { emit(["session": s.id.uuidString, "restored": r.restored, "gone": r.gone, "failed": r.failed]) }
            else { print("Put back \(r.restored) items.\(r.gone > 0 ? " \(r.gone) were no longer in the Trash." : "")\(r.failed > 0 ? " \(r.failed) couldn't be put back." : "")") }
            return r.restored == 0 && (r.gone + r.failed) > 0 ? 70 : 0
        }
    }

    // MARK: money

    static func money(_ opts: Options) -> Int32 {
        return MainActor.assumeIsolated { () -> Int32 in
            let procs = SystemInfo.processes()
            let memory = SystemInfo.memory()
            let space = DiskSpace.current()
            let health = SystemInfo.health()
            let hw = MoneyInfo.hardware()
            let verdict = MoneyInfo.macVerdict(hw: hw, health: health, memory: memory, space: space)
            let battery = MoneyInfo.batteryDecision(health.battery)
            let subs = MoneyInfo.subscriptions()
            let clouds = MoneyInfo.cloudDrives()
            let storage = MoneyInfo.storageMath()
            let alts = MoneyInfo.builtInAlternatives()
            let plan = Int(opts.values["--plan"] ?? "") ?? UserDefaults.standard.integer(forKey: "planMbps")
            var speed: SpeedTest?
            if opts.flags.contains("--speedtest") { speed = MoneyInfo.speedTest() }
            _ = procs
            if opts.json {
                var out: [String: Any] = [
                    "mac": ["model": hw.model, "chip": hw.chip, "memoryGB": hw.memoryGB, "appleSilicon": hw.appleSilicon,
                            "verdict": verdict.level == .good ? "fine" : (verdict.level == .watch ? "one cheap fix" : "replace"), "headline": verdict.headline, "reasons": verdict.reasons, "cheapestFix": verdict.cheapestFix],
                    "subscriptions": subs.map { ["vendor": $0.vendor, "app": $0.name, "lastUsed": iso($0.lastUsed) as Any, "daysIdle": $0.daysIdle as Any, "manage": $0.manageURL, "note": $0.note] },
                    "cloudDrives": clouds.map { ["name": $0.name, "installed": $0.installed, "running": $0.running, "localBytes": $0.localBytes as Any] },
                    "storage": ["freeBytes": storage.space?.free as Any, "totalBytes": storage.space?.total as Any, "safeBytes": storage.safeBytes, "reviewBytes": storage.reviewBytes, "icloudLocalBytes": storage.icloudLocalBytes as Any],
                    "alternatives": alts.map { ["app": $0.installedApp, "builtIn": $0.builtIn, "note": $0.note] },
                ]
                if let b = battery { out["battery"] = ["level": b.level == .good ? "fine" : (b.level == .watch ? "watch" : "replace"), "text": b.text] }
                if let s = speed { out["speedTest"] = ["mbps": s.mbps, "latencyMs": s.latencyMs as Any, "planMbps": plan, "bytes": s.bytes, "seconds": s.seconds] }
                emit(out)
                return 0
            }
            let dot = verdict.level == .good ? "🟢" : (verdict.level == .watch ? "🟡" : "🔴")
            print("\(dot) \(verdict.headline)  (\(hw.model) · \(hw.chip) · \(hw.memoryGB) GB)")
            for r in verdict.reasons { print("   • \(r)") }
            print("   \(verdict.cheapestFix)")
            if let b = battery { print("\n== Battery\n   \(b.text)") }
            print("\n== Subscription apps (Tidy can't see your bills; these are questions)")
            if subs.isEmpty { print("   none found") }
            for s in subs { print("   \(pad(s.vendor, 24)) \(s.lastUsed == nil ? "never opened" : (s.daysIdle! >= 60 ? "not opened in \(s.daysIdle!) days" : "used \(s.daysIdle!) days ago"))  → \(s.manageURL)") }
            let active = clouds.filter(\.installed)
            print("\n== Cloud drives: \(active.map { "\($0.name)\($0.localBytes.map { " (\(Bytes.string($0)) local)" } ?? "")" }.joined(separator: ", "))\(active.count >= 2 ? "  — most households need one" : "")")
            if let sp = storage.space {
                print("\n== Storage: \(Bytes.string(sp.free)) free · a tidy frees \(Bytes.string(storage.safeBytes)) safely + \(Bytes.string(storage.reviewBytes)) to review\(storage.icloudLocalBytes.map { " · iCloud Drive keeps \(Bytes.string($0)) locally" } ?? "")")
            }
            if let s = speed {
                print("\n== Internet: \(Int(s.mbps)) Mbps download\(s.latencyMs.map { String(format: " · %.0f ms", $0) } ?? "")\(plan > 0 ? " · plan \(plan) Mbps (\(Int(s.mbps / Double(plan) * 100))%)" : " · pass --plan <mbps> to compare")")
            }
            if !alts.isEmpty { print("\n== Built in for free"); for a in alts { print("   \(a.installedApp) → \(a.builtIn): \(a.note)") } }
            return 0
        }
    }

    // MARK: sort

    static func sort(_ opts: Options) -> Int32 {
        var folders: [URL] = []
        if opts.flags.contains("--desktop") { folders.append(Scanner.home.appendingPathComponent("Desktop")) }
        if opts.flags.contains("--downloads") { folders.append(Scanner.home.appendingPathComponent("Downloads")) }
        if folders.isEmpty { folders = [Scanner.home.appendingPathComponent("Desktop"), Scanner.home.appendingPathComponent("Downloads")] }
        let days = Int(opts.values["--older-than"] ?? "") ?? 7
        let moves = Sorter.plan(folders: folders, olderThanDays: days)
        let total = moves.reduce(0) { $0 + $1.size }
        let planJSON = moves.map { ["from": $0.from, "to": $0.to, "category": $0.category, "bytes": $0.size] }
        if moves.isEmpty {
            if opts.json { emit(["moved": 0, "message": "nothing to file"]) } else { print("Nothing to file: no loose files untouched for \(days)+ days. Nothing was changed.") }
            return 0
        }
        if opts.flags.contains("--dry-run") || (!opts.yes && !isTTY) {
            if opts.json { emit(["dryRun": true, "wouldMove": planJSON, "bytes": total]) }
            else {
                print("Would file \(moves.count) files (\(Bytes.string(total))):")
                for c in Sorter.categories { let ms = moves.filter { $0.category == c }; if !ms.isEmpty { print("   \(pad(c, 12)) \(ms.count) files") } }
                print(opts.flags.contains("--dry-run") ? "Nothing was changed (dry run)." : "Re-run with --yes to file them. Nothing was changed.")
            }
            return opts.flags.contains("--dry-run") ? 0 : 3
        }
        if !opts.yes {
            print("File \(moves.count) files (\(Bytes.string(total))) into Tidied folders by type?")
            for c in Sorter.categories { let ms = moves.filter { $0.category == c }; if !ms.isEmpty { print("   \(pad(c, 12)) \(ms.count) files") } }
            if !confirm("Continue?") { print("Nothing was changed."); return 3 }
        }
        let session = Sorter.execute(moves)
        MainActor.assumeIsolated { History.shared.add(session) }
        if opts.json { emit(["session": session.id.uuidString, "moved": session.movedCount, "failed": session.failedCount, "bytes": session.totalSize]) }
        else { print("Filed \(session.movedCount) files into Tidied folders.\(session.failedCount > 0 ? " \(session.failedCount) couldn't be moved." : "") `tidymac restore last` puts them back.") }
        return 0
    }

    // MARK: report

    static func report(_ opts: Options) -> Int32 {
        let md = opts.flags.contains("--md")
        let defaultName = "Tidy checkup \(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")).\(md ? "md" : "html")"
        let out = URL(fileURLWithPath: opts.values["--out"] ?? Scanner.home.appendingPathComponent("Desktop/\(defaultName)").path)
        let data = MainActor.assumeIsolated { Report.gather() }
        if opts.values["--out"] == "-" { print(md ? Report.markdown(data) : Report.html(data)); return 0 }
        do { try Report.write(data, to: out, html: !md) } catch { return fail("couldn't write \(out.path): \(error.localizedDescription)", json: opts.json) }
        if opts.json { emit(["file": out.path, "verdict": data.verdict]) } else { print("Report written to \(out.path)") }
        if opts.flags.contains("--open") { NSWorkspace.shared.open(out) }
        return 0
    }

    // MARK: trash / disk

    static func trash(_ opts: Options) -> Int32 {
        let t = Scanner.trashState()
        if opts.flags.contains("--empty") {
            if !opts.yes {
                if isTTY {
                    if !confirm("Permanently remove everything in the Trash\(t.readable ? " (\(t.count) items, \(Bytes.string(t.size)))" : "")? There's no getting it back.") { print("Nothing was changed."); return 3 }
                } else { print("Re-run with --yes to empty the Trash. Nothing was changed."); return 3 }
            }
            if let e = Scanner.emptyTrash() { return fail(e, json: opts.json) }
            if opts.json { emit(["emptied": true, "freedBytes": t.size]) } else { print("Trash emptied\(t.readable ? ", \(Bytes.string(t.size)) freed" : "").") }
            return 0
        }
        if opts.json { emit(["readable": t.readable, "bytes": t.size, "items": t.count]) }
        else { print(t.readable ? "Trash: \(t.count) items, \(Bytes.string(t.size)). `tidymac trash --empty` removes them for good." : "Trash size isn't readable without Full Disk Access. `tidymac trash --empty` still works.") }
        return 0
    }

    static func disk(_ opts: Options) -> Int32 {
        guard Capabilities.diskutil else { return fail("diskutil is not available on this Mac", json: opts.json) }
        do {
            let scan = try DiskUtil.scan()
            if opts.json {
                func node(_ n: DiskNode) -> [String: Any] {
                    var d: [String: Any] = ["kind": n.kind.rawValue, "name": n.name, "device": n.deviceIdentifier, "type": n.content, "bytes": n.size,
                                            "roles": n.roles.map(\.rawValue), "internal": n.isInternal, "bootPath": n.onBootPath, "booted": n.isBootDevice, "sealed": n.sealed, "encrypted": n.encrypted]
                    if let m = n.mountPoint { d["mountPoint"] = m }
                    if let u = n.used { d["usedBytes"] = u }
                    if let f = n.free { d["freeBytes"] = f }
                    if !n.children.isEmpty { d["children"] = n.children.map(node) }
                    return d
                }
                let b = scan.boot
                emit(["boot": ["device": b.bootDevice, "volume": b.bootVolumeName, "container": b.containerRef, "physicalDisks": b.physicalDisks, "dataVolume": b.dataVolume as Any,
                               "macOS": b.osVersion, "build": b.osBuild, "snapshot": b.bootedFromSnapshot, "sealed": b.sealed, "fileVault": b.fileVault],
                      "disks": scan.roots.map(node)])
                return 0
            }
            Dump.printDiskMap(scan)
            return 0
        } catch {
            return fail("\(error)", json: opts.json)
        }
    }
}
