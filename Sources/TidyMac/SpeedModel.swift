//  Model for the Speed tab. Two refresh rhythms: refreshNow() every four seconds while the tab
//  is visible (processes, memory, sync CPU history), and refreshSlow() on demand for anything
//  that shells out to system_profiler, tmutil, pmset, and friends. `findings` rolls everything
//  into the green / yellow / red verdict at the top of the tab.

import Foundation
import AppKit
import Observation

@MainActor
@Observable
final class SpeedModel {
    // Right now (refreshed every few seconds while visible)
    var apps: [AppLoad] = []
    var space: DiskSpace?
    var memory: MemoryInfo?
    var background: String?
    var uptimeDays: Double = 0

    // Slower facts (refreshed on demand)
    var health: HealthReport?
    var updates: [String]?          // nil = not checked yet
    var checkingUpdates = false
    var loginItems: [LoginItem] = []
    var loginItemsError: String?
    var agents: [AgentInfo] = []
    var browsers: [BrowserInfo] = []
    var loadingSlow = false
    var message: String?

    var reduceMotion: Bool? = SystemInfo.accessibilityFlag("reduceMotion")
    var reduceTransparency: Bool? = SystemInfo.accessibilityFlag("reduceTransparency")

    // Second batch
    var network: NetworkInfo?
    var checkingNetwork = false
    var sync: [SyncStatus] = []
    private var cpuHistory: [String: [Double]] = [:]
    var timeMachine: TimeMachineInfo?
    var appUpdates: [AppUpdateInfo]?
    var checkingAppUpdates = false
    var rosettaApps: [RosettaApp]?
    var menuBarApps: [AppLoad] = []
    var widgets: [AppLoad] = []
    var printers: [PrinterInfo]?
    var power: PowerInfo?
    var sleep: SleepInfo?
    var volumes: [VolumeBench] = SystemInfo2.volumes()
    var benchmarking: String?

    // Third batch
    var boot: BootTiming?
    var safety: [SafetyCheck]?
    var deviceBatteries: [DeviceBattery]?
    var defaultApps: [DefaultAppSlot] = []
    var fixRunning: String?

    /// Set by demo mode: skip every real refresh so sample data stays put.
    var demo = false
    private var timer: Timer?
    private var loadedOnce = false

    // MARK: Verdict

    struct Finding: Identifiable {
        var id: String { title }
        var level: Verdict
        var title: String
        var detail: String
    }

    var findings: [Finding] {
        var f: [Finding] = []
        if let s = space {
            let freeFrac = 1 - s.usedFraction
            if freeFrac < 0.05 { f.append(Finding(level: .act, title: String(localized: "Disk almost full"), detail: String(localized: "Only \(Bytes.string(s.free)) free. macOS slows down badly below 5%. Run Tidy Up."))) }
            else if freeFrac < 0.10 { f.append(Finding(level: .watch, title: String(localized: "Disk getting full"), detail: String(localized: "\(Bytes.string(s.free)) free. Keep at least 10% free for macOS to work well."))) }
        }
        if let m = memory {
            if m.pressure >= 4 { f.append(Finding(level: .act, title: String(localized: "Memory is critical"), detail: String(localized: "Apps are fighting for memory. Quit the biggest ones below, or restart."))) }
            else if m.pressure >= 2 { f.append(Finding(level: .watch, title: String(localized: "Memory is under pressure"), detail: String(localized: "Things will feel slower. Quitting a few apps helps."))) }
        }
        if let h = health {
            if let l = h.cpuSpeedLimit, l < 80 { f.append(Finding(level: .act, title: String(localized: "The chip is being slowed to stay cool"), detail: String(localized: "Running at \(l)% speed. Check for a stuck process below, clear the vents, and let it cool."))) }
            if h.thermal == String(localized: "Hot") || h.thermal == String(localized: "Very hot") { f.append(Finding(level: .watch, title: String(localized: "Running hot"), detail: String(localized: "See what's busy below. Heavy work in the background is usually the reason."))) }
            if let ok = h.smartOK, !ok { f.append(Finding(level: .act, title: String(localized: "The drive reports a problem"), detail: String(localized: "Back up now and have the drive checked."))) }
            if let b = h.battery {
                if let c = b.condition, c.lowercased() != "good", c.lowercased() != "normal" { f.append(Finding(level: .act, title: String(localized: "Battery needs service"), detail: String(localized: "macOS reports: \(c)."))) }
                else if let p = b.healthPercent, p < 80 { f.append(Finding(level: .watch, title: String(localized: "Battery is wearing out"), detail: String(localized: "Holds \(p)% of its original charge."))) }
            }
            if h.uptimeDays >= 14 { f.append(Finding(level: memory.map { $0.pressure >= 2 } ?? false ? .watch : .watch, title: String(localized: "It's been \(Int(h.uptimeDays)) days since a restart"), detail: String(localized: "A restart clears out memory and finishes pending updates. It takes a minute."))) }
        }
        if let u = updates, !u.isEmpty { f.append(Finding(level: .watch, title: String(localized: "\(u.count) macOS updates waiting"), detail: u.prefix(3).joined(separator: ", "))) }
        if let checks = safety {
            let off = checks.filter { $0.ok == false }
            if !off.isEmpty { f.append(Finding(level: .watch, title: off.count == 1 ? String(localized: "One safety switch is off") : String(localized: "\(off.count) safety switches are off"), detail: off.map(\.name).joined(separator: ", "))) }
        }
        if let devs = deviceBatteries, let low = devs.first(where: { ($0.lowest ?? 100) < 20 }) {
            f.append(Finding(level: .watch, title: String(localized: "\(low.name) needs charging"), detail: String(localized: "Down to \(low.lowest ?? 0)%.")))
        }
        let heavyAgents = agents.filter { !$0.system && $0.loaded && $0.memory > 200_000_000 }
        if !heavyAgents.isEmpty { f.append(Finding(level: .watch, title: String(localized: "\(heavyAgents.count) background helpers using a lot of memory"), detail: heavyAgents.prefix(3).map(\.vendor).joined(separator: ", "))) }
        return f
    }

    var verdict: Verdict {
        if findings.contains(where: { $0.level == .act }) { return .act }
        if findings.contains(where: { $0.level == .watch }) { return .watch }
        return .good
    }

    // MARK: Refresh

    func startLive() {
        guard !demo else { return }
        refreshNow()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { _ in
            Task { @MainActor in self.refreshNow() }
        }
        if !loadedOnce { loadedOnce = true; refreshSlow() }
    }

    func stopLive() {
        timer?.invalidate()
        timer = nil
    }

    func refreshNow() {
        Task {
            let procs = await Task.detached { SystemInfo.processes() }.value
            apps = SystemInfo.appLoads(procs)
            space = DiskSpace.current()
            memory = SystemInfo.memory()
            background = SystemInfo.backgroundActivity(procs)
            uptimeDays = SystemInfo.uptimeDays
            // Sync clients: keep a short CPU history so "stuck" means sustained, not a blip.
            for c in SystemInfo2.syncClients {
                let cpu = procs.filter { URL(fileURLWithPath: $0.command).lastPathComponent == c.process || $0.command.contains("/\(c.process).app/") }.reduce(0) { $0 + $1.cpu }
                cpuHistory[c.process, default: []].append(cpu)
                if cpuHistory[c.process]!.count > 8 { cpuHistory[c.process]!.removeFirst() }
            }
            sync = SystemInfo2.sync(procs, history: cpuHistory)
            menuBarApps = SystemInfo2.menuBarApps(procs)
            widgets = SystemInfo2.widgets(procs)
            if !agents.isEmpty {
                // keep per-agent load fresh without re-reading plists
                for i in agents.indices {
                    let m = procs.filter { !agents[i].program.isEmpty && $0.command.hasPrefix(agents[i].program) }
                    agents[i].cpu = m.reduce(0) { $0 + $1.cpu }
                    agents[i].memory = m.reduce(0) { $0 + $1.rss }
                }
            }
        }
    }

    func refreshSlow() {
        guard !loadingSlow, !demo else { return }
        loadingSlow = true
        reduceMotion = SystemInfo.accessibilityFlag("reduceMotion")
        reduceTransparency = SystemInfo.accessibilityFlag("reduceTransparency")
        Task {
            async let h = Task.detached { SystemInfo.health() }.value
            async let procs = Task.detached { SystemInfo.processes() }.value
            async let b = Task.detached { SystemInfo.browsers() }.value
            let p = await procs
            agents = await Task.detached { SystemInfo.agents(p) }.value
            browsers = await b
            health = await h
            loadingSlow = false
        }
        Task { timeMachine = await Task.detached { SystemInfo2.timeMachine() }.value }
        Task { rosettaApps = await Task.detached { SystemInfo2.rosettaApps() }.value }
        Task { printers = await Task.detached { SystemInfo2.printers() }.value }
        Task { power = await Task.detached { SystemInfo2.power() }.value }
        Task { sleep = await Task.detached { SystemInfo2.sleep() }.value }
        Task { safety = await Task.detached { SystemInfo3.safety() }.value }
        Task { deviceBatteries = await Task.detached { SystemInfo3.deviceBatteries() }.value }
        defaultApps = SystemInfo3.defaultApps()
        refreshNetwork()
        Task {
            // System Events may prompt for permission the first time; do it on the main thread.
            let r = SystemInfo.loginItems()
            loginItems = r.items
            loginItemsError = r.denied ? String(localized: "Tidy for Mac isn't allowed to read login items. Allow it under Privacy & Security > Automation > Tidy for Mac > System Events.") : nil
            let li = loginItems, ag = agents
            boot = await Task.detached { MoneyInfo.bootTiming(SystemInfo.processes(), loginItems: li, agents: ag) }.value
        }
    }

    func checkUpdates() {
        guard !checkingUpdates else { return }
        checkingUpdates = true
        Task {
            updates = await Task.detached { SystemInfo.pendingUpdates() }.value
            checkingUpdates = false
        }
    }

    func refreshNetwork() {
        guard !checkingNetwork else { return }
        checkingNetwork = true
        Task {
            network = await Task.detached { SystemInfo2.network() }.value
            checkingNetwork = false
        }
    }

    func checkAppUpdates() {
        guard !checkingAppUpdates else { return }
        checkingAppUpdates = true
        Task {
            appUpdates = await Task.detached { SystemInfo2.appUpdates() }.value
            checkingAppUpdates = false
        }
    }

    func restartSync(_ s: SyncStatus) {
        Task {
            let err = await Task.detached { SystemInfo2.restartSync(s) }.value
            message = err ?? String(localized: "\(s.name) restarted. Give it a minute to settle.")
            cpuHistory[s.processName] = []
        }
    }

    func clearPrintJobs(_ p: PrinterInfo) {
        let err = SystemInfo2.clearJobs(p.name)
        message = err ?? String(localized: "Cleared waiting jobs for \(p.name).")
        Task { printers = await Task.detached { SystemInfo2.printers() }.value }
    }

    func removePrinter(_ p: PrinterInfo) {
        if let err = SystemInfo2.removePrinter(p.name) { message = err; return }
        message = String(localized: "Removed \(p.name). Add it back from Printers & Scanners if you need it.")
        History.shared.add(TidySession(id: UUID(), date: Date(), automatic: false, label: String(localized: "Removed printer \(p.name)"), records: []))
        Task { printers = await Task.detached { SystemInfo2.printers() }.value }
    }

    func benchmark(_ v: VolumeBench) {
        guard benchmarking == nil else { return }
        benchmarking = v.id
        let path = v.path
        Task {
            let r = await Task.detached { SystemInfo2.benchmark(path) }.value
            if let i = volumes.firstIndex(where: { $0.id == v.id }) {
                volumes[i].writeMBs = r?.write
                volumes[i].readMBs = r?.read
            }
            if r == nil { message = String(localized: "Couldn't write a test file on \(v.name).") }
            benchmarking = nil
        }
    }

    func setDefault(_ slot: DefaultAppSlot, _ path: String) {
        SystemInfo3.setDefault(slot, to: path) { [weak self] err in
            guard let self else { return }
            if let err { self.message = err } else {
                self.message = String(localized: "\(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent) now opens \(slot.name.lowercased()).")
            }
            self.defaultApps = SystemInfo3.defaultApps()
        }
    }

    func runFix(_ f: QuickFix) {
        fixRunning = f.key
        Task {
            let msg = await Task.detached { SystemInfo3.run(f) }.value
            message = msg
            fixRunning = nil
        }
    }

    // MARK: Actions

    func quit(_ app: AppLoad, force: Bool = false) {
        guard let path = app.bundlePath else { return }
        let running = NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.path == path }
        for r in running { if force { r.forceTerminate() } else { r.terminate() } }
        message = force ? String(localized: "Force-quit \(app.name).") : String(localized: "Asked \(app.name) to quit. Unsaved work will prompt first.")
        Task { try? await Task.sleep(for: .seconds(1.5)); refreshNow() }
    }

    func removeLoginItem(_ item: LoginItem) {
        if let e = SystemInfo.removeLoginItem(item.name) { message = e; return }
        loginItems.removeAll { $0.id == item.id }
        History.shared.add(TidySession(id: UUID(), date: Date(), automatic: false,
                                       label: String(localized: "Removed login item \(item.name)"), records: []))
        message = String(localized: "\(item.name) will no longer open at login. Re-add it in System Settings > General > Login Items if you change your mind.")
    }

    func toggleAgent(_ a: AgentInfo) {
        let err = a.disabledByTidy ? SystemInfo.enableAgent(a) : SystemInfo.disableAgent(a)
        if let err { message = err; return }
        if !a.disabledByTidy {
            History.shared.add(TidySession(id: UUID(), date: Date(), automatic: false,
                                           label: String(localized: "Turned off background helper \(a.vendor)"),
                                           records: [TidyRecord(id: UUID(), name: a.label, originalPath: a.plistPath,
                                                                trashPath: SystemInfo.disabledAgentsDir.appendingPathComponent(URL(fileURLWithPath: a.plistPath).lastPathComponent).path,
                                                                size: 0, restored: false, kind: nil)]))
        }
        message = a.disabledByTidy ? String(localized: "\(a.vendor) helper turned back on.") : String(localized: "\(a.vendor) helper turned off. It won't start at next login. Turn it back on here any time.")
        Task {
            let procs = await Task.detached { SystemInfo.processes() }.value
            agents = await Task.detached { SystemInfo.agents(procs) }.value
        }
    }

    func clearBrowserCaches(_ b: BrowserInfo) {
        guard !b.running else { message = String(localized: "Quit \(b.name) first, then try again."); return }
        let paths = b.profiles.flatMap(\.cachePaths)
        Task {
            var records: [TidyRecord] = []
            for p in paths {
                let size = await Task.detached { Scanner.size(of: URL(fileURLWithPath: p)) }.value
                let t = await Task.detached { Scanner.moveToTrash(p) }.value
                records.append(TidyRecord(id: UUID(), name: URL(fileURLWithPath: p).lastPathComponent, originalPath: p, trashPath: t, size: size, restored: false, kind: .caches))
            }
            let s = TidySession(id: UUID(), date: Date(), automatic: false, label: String(localized: "Cleared \(b.name) site data"), records: records)
            History.shared.add(s)
            message = String(localized: "Moved \(Bytes.string(s.totalSize)) of \(b.name) site data to the Trash. Sites will reload fresh; you stay signed in.")
            browsers = await Task.detached { SystemInfo.browsers() }.value
        }
    }

    func manageExtensions(_ b: BrowserInfo) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: b.bundleID) else { return }
        let scheme = b.bundleID == "com.microsoft.edgemac" ? "edge" : (b.bundleID == "com.brave.Browser" ? "brave" : "chrome")
        let cfg = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([URL(string: "\(scheme)://extensions")!], withApplicationAt: app, configuration: cfg)
    }

    func restart() {
        if let e = SystemInfo.restart() { message = e }
    }
}
