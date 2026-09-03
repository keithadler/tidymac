import ServiceManagement
//  Demo data and screenshot rendering.
//
//  `TidyMac --screenshots <dir>` fills every model with made-up sample data, renders each window
//  off-screen into a PNG, and exits. The images in docs/screenshots come from this, so they never
//  contain anything from a real disk and can be regenerated after any UI change with:
//      "build/Tidy for Mac.app/Contents/MacOS/TidyMac" --screenshots docs/screenshots
//  Rendering uses NSView.cacheDisplay on an off-screen window, which needs no screen-recording
//  permission and includes AppKit-backed controls (lists, toggles) that ImageRenderer would skip.

import SwiftUI
import AppKit

enum Demo {
    static var isActive: Bool { CommandLine.arguments.contains("--screenshots") }

    // MARK: Sample data

    @MainActor
    static func cleanup() -> CleanupModel {
        let m = CleanupModel()
        m.space = DiskSpace(total: 494_384_795_648, free: 212_000_000_000)
        m.trash = TrashState(size: 3_200_000_000, count: 41, readable: true)
        func item(_ name: String, _ detail: String, _ mb: Double, _ on: Bool, why: String = "Sample item.") -> CleanItem {
            CleanItem(id: name, paths: ["/Users/sam/Library/\(name)"], name: name, detail: detail, size: Int64(mb * 1_000_000), selected: on, why: why)
        }
        m.categories = [
            CleanCategory(kind: .caches, items: [
                item("Safari", "Cache · used today", 1240, true),
                item("Photo Editor", "Cache · last used 2 months ago", 612, true),
                item("Music", "Cache · used 3 days ago", 340, true),
                item("Maps", "Cache · used today", 88, true),
            ], expanded: true),
            CleanCategory(kind: .logs, items: [
                item("Backup Helper", "Logs · used today", 96, true),
                item("Printer Utility", "Logs · last used 5 months ago", 41, true),
            ]),
            CleanCategory(kind: .installers, items: [
                item("PhotoEditor-4.2.dmg", "Downloaded Mar 3, 2026", 410, true),
                item("Zoom.pkg", "Downloaded Jun 18, 2026", 92, true),
            ]),
            CleanCategory(kind: .duplicates, items: [
                item("Holiday 2025.mov", "2 identical copies · keeping the one in Movies", 1850, true),
                item("Tax return 2024.pdf", "2 identical copies · keeping the one in Documents", 4, true),
            ]),
            CleanCategory(kind: .leftovers, items: [
                item("Old Video Converter", "settings, support files · last used Nov 2024", 210, false),
                item("Trial Screen Recorder", "app container · last used 8 months ago", 96, false),
            ]),
            CleanCategory(kind: .iosBackups, items: [
                item("Sam's iPhone", "iPhone 12 · backed up Jan 9, 2025", 8_900, false),
            ]),
            CleanCategory(kind: .bigFiles, items: [
                item("Kitchen renovation.mp4", "in Movies · last used 4 months ago", 6_400, false),
                item("Family photos 2023.zip", "in Downloads · last used Aug 2025", 2_100, false),
            ]),
        ]
        m.phase = .ready
        return m
    }

    @MainActor
    static func speed() -> SpeedModel {
        let m = SpeedModel()
        m.demo = true
        m.space = DiskSpace(total: 494_384_795_648, free: 212_000_000_000)
        m.memory = MemoryInfo(total: 17_179_869_184, used: 11_200_000_000, pressure: 1)
        m.uptimeDays = 17
        m.health = HealthReport(battery: BatteryInfo(cycles: 412, healthPercent: 88, condition: "Good"), smartOK: true,
                                uptimeDays: 17, thermal: "Cool", cpuSpeedLimit: nil, osVersion: "15.5")
        m.apps = [
            AppLoad(id: "chrome", name: "Google Chrome", bundlePath: nil, cpu: 38, memory: 5_900_000_000, processes: 54, isApp: true),
            AppLoad(id: "photos", name: "Photos", bundlePath: nil, cpu: 4, memory: 1_300_000_000, processes: 2, isApp: true),
            AppLoad(id: "mail", name: "Mail", bundlePath: nil, cpu: 1, memory: 640_000_000, processes: 1, isApp: true),
            AppLoad(id: "zoom", name: "Zoom", bundlePath: nil, cpu: 0, memory: 410_000_000, processes: 3, isApp: true),
            AppLoad(id: "music", name: "Music", bundlePath: nil, cpu: 2, memory: 290_000_000, processes: 1, isApp: true),
        ]
        m.loginItems = [LoginItem(name: "Zoom", path: "/Applications/zoom.us.app"), LoginItem(name: "Photo Sync Helper", path: "/Applications/Photo Sync.app")]
        m.agents = [
            AgentInfo(plistPath: "/Users/sam/Library/LaunchAgents/com.example.cloudsync.plist", label: "com.example.cloudsync", program: "", vendor: "Example", loaded: true, runAtLoad: true, system: false, disabledByTidy: false, cpu: 0.4, memory: 180_000_000),
            AgentInfo(plistPath: "/Users/sam/Library/LaunchAgents/com.printco.monitor.plist", label: "com.printco.monitor", program: "", vendor: "Printco", loaded: true, runAtLoad: true, system: false, disabledByTidy: false, cpu: 0, memory: 22_000_000),
        ]
        m.browsers = [BrowserInfo(name: "Google Chrome", bundleID: "com.google.Chrome", running: true,
                                  profiles: [BrowserProfile(id: "p1", name: "Sam", siteData: 4_800_000_000, cachePaths: []),
                                             BrowserProfile(id: "p2", name: "Work", siteData: 1_900_000_000, cachePaths: [])],
                                  extensions: [BrowserExtension(id: "e1", name: "Password Manager", size: 48_000_000, profile: "Sam"),
                                               BrowserExtension(id: "e2", name: "Ad Blocker", size: 31_000_000, profile: "Sam"),
                                               BrowserExtension(id: "e3", name: "Coupon Finder", size: 22_000_000, profile: "Sam")])]
        m.network = NetworkInfo(ssid: "Home Wi-Fi", channel: "36 (5GHz, 80MHz)", band: "5 GHz", phyMode: "802.11ax", signal: -52, noise: -92, txRate: 866, fasterBandAvailable: false, dnsMillis: 24, gateway: "192.168.1.1", gatewayMillis: 4.1)
        m.sync = [SyncStatus(name: "iCloud Drive", bundleID: nil, processName: "bird", running: true, cpuNow: 1, stuck: false)]
        m.timeMachine = TimeMachineInfo(configured: true, destination: "Backup Drive", lastBackup: Date().addingTimeInterval(-3 * 86400), localSnapshots: [Date().addingTimeInterval(-86400), Date()])
        m.updates = []
        m.rosettaApps = [RosettaApp(name: "Old Video Converter", path: "/Applications/Old Video Converter.app")]
        m.menuBarApps = [AppLoad(id: "mb1", name: "Photo Sync", bundlePath: nil, cpu: 0, memory: 120_000_000, processes: 1, isApp: true)]
        m.widgets = [AppLoad(id: "apple-widgets", name: "Apple's built-in widgets", bundlePath: nil, cpu: 0, memory: 240_000_000, processes: 22, isApp: false)]
        m.printers = [PrinterInfo(name: "Kitchen_Printer", isDefault: true, state: "idle", reason: nil, jobs: 0, uri: nil),
                      PrinterInfo(name: "Old_Office_Printer", isDefault: false, state: "disabled", reason: "Unable to connect", jobs: 2, uri: nil)]
        m.power = PowerInfo(onBattery: true, percent: 64, charging: false, lowPowerMode: false, displaySleepMinutes: 10, settings: [:])
        m.sleep = SleepInfo(assertions: [SleepInfo.Assertion(process: "Music", type: "PreventUserIdleSystemSleep", reason: "Playing audio")],
                            scheduled: [], recentWakes: [
                                SleepInfo.Wake(when: "2026-09-02 08:12", reason: "lid", friendly: "You opened the lid"),
                                SleepInfo.Wake(when: "2026-09-02 03:40", reason: "rtc", friendly: "Scheduled maintenance wake (normal)"),
                                SleepInfo.Wake(when: "2026-09-01 22:15", reason: "bt", friendly: "A Bluetooth device woke it")],
                            wakeForNetwork: true, powerNap: true, proximityWake: false, tcpKeepAlive: true)
        m.volumes = [VolumeBench(path: "/", name: "Startup disk", isInternal: true, writeMBs: 1490, readMBs: 2050),
                     VolumeBench(path: "/Volumes/Backup Drive", name: "Backup Drive", isInternal: false, writeMBs: nil, readMBs: nil)]
        m.safety = [
            SafetyCheck(key: "filevault", name: "Disk encryption (FileVault)", ok: true, detail: "On. If the Mac is lost, nobody can read what's on it.", fixPane: nil),
            SafetyCheck(key: "firewall", name: "Firewall", ok: false, detail: "Off. Worth turning on, especially on public Wi-Fi.", fixPane: "x"),
            SafetyCheck(key: "updates", name: "Automatic updates", ok: true, detail: "On, including macOS updates. Security fixes arrive on their own.", fixPane: nil),
            SafetyCheck(key: "lock", name: "Lock when the screen sleeps", ok: true, detail: "Asks for the password within 5 minutes of the screen sleeping. Good.", fixPane: nil),
            SafetyCheck(key: "gatekeeper", name: "App checking (Gatekeeper)", ok: true, detail: "On. Apps from unknown makers get checked before they open.", fixPane: nil),
        ]
        m.deviceBatteries = [DeviceBattery(name: "Sam's AirPods", kind: "Headphones", levels: [("Left", 72), ("Right", 70), ("Case", 15)]),
                             DeviceBattery(name: "Magic Mouse", kind: "Mouse", levels: [("", 41)])]
        m.defaultApps = [
            DefaultAppSlot(key: "http", name: "Web links", current: "/Applications/Safari.app", candidates: ["/Applications/Safari.app"]),
            DefaultAppSlot(key: "mailto", name: "Email links", current: "/System/Applications/Mail.app", candidates: ["/System/Applications/Mail.app"]),
            DefaultAppSlot(key: "pdf", name: "PDF files", current: "/System/Applications/Preview.app", candidates: ["/System/Applications/Preview.app"]),
        ]
        return m
    }

    @MainActor
    static func history() {
        func rec(_ n: String, _ mb: Double, kind: CleanKind) -> TidyRecord {
            TidyRecord(id: UUID(), name: n, originalPath: "/Users/sam/Library/Caches/\(n)", trashPath: "/Users/sam/.Trash/\(n)", size: Int64(mb * 1_000_000), restored: false, kind: kind)
        }
        History.shared.sessions = [
            TidySession(id: UUID(), date: Date().addingTimeInterval(-3600), automatic: false, label: nil,
                        records: [rec("Safari", 1240, kind: .caches), rec("Photo Editor", 612, kind: .caches), rec("PhotoEditor-4.2.dmg", 410, kind: .installers)]),
            TidySession(id: UUID(), date: Date().addingTimeInterval(-7 * 86400), automatic: true, label: "Quiet tidy",
                        records: [rec("Music", 340, kind: .caches), rec("Backup Helper", 96, kind: .logs)]),
            TidySession(id: UUID(), date: Date().addingTimeInterval(-20 * 86400), automatic: false, label: "Uninstalled Old Video Converter",
                        records: [rec("Old Video Converter", 210, kind: .leftovers)]),
        ]
    }

    @MainActor
    static func uninstall() -> UninstallModel {
        let m = UninstallModel()
        m.loaded = true
        let icon = NSWorkspace.shared.icon(for: .applicationBundle)
        m.apps = [
            UninstallModel.AppEntry(path: "/Applications/Old Video Converter.app", name: "Old Video Converter", bundleID: "com.example.converter", size: 210_000_000, icon: icon),
            UninstallModel.AppEntry(path: "/Applications/Photo Editor.app", name: "Photo Editor", bundleID: "com.example.photoeditor", size: 890_000_000, icon: icon),
            UninstallModel.AppEntry(path: "/Applications/Trial Screen Recorder.app", name: "Trial Screen Recorder", bundleID: "com.example.recorder", size: 96_000_000, icon: icon),
            UninstallModel.AppEntry(path: "/Applications/Zoom.app", name: "Zoom", bundleID: "us.zoom.xos", size: 815_000_000, icon: icon),
        ]
        m.selected = m.apps[0]
        m.related = [
            CleanItem(id: "r1", paths: ["/Users/sam/Library/Application Support/Old Video Converter"], name: "support files · Old Video Converter", detail: "~/Library/Application Support", size: 140_000_000, selected: true),
            CleanItem(id: "r2", paths: ["/Users/sam/Library/Caches/com.example.converter"], name: "cache · com.example.converter", detail: "~/Library/Caches", size: 62_000_000, selected: true),
            CleanItem(id: "r3", paths: ["/Users/sam/Library/Preferences/com.example.converter.plist"], name: "settings · com.example.converter.plist", detail: "~/Library/Preferences", size: 12_000, selected: true),
        ]
        return m
    }

    @MainActor
    static func spaceMap() -> SpaceModel {
        let m = SpaceModel()
        m.demo = true
        func n(_ name: String, _ gb: Double, _ kids: [SpaceNode] = []) -> SpaceNode {
            SpaceNode(id: "/Users/sam/\(name)", name: name, size: Int64(gb * 1_000_000_000), isDirectory: !kids.isEmpty || gb > 1, children: kids)
        }
        let root = n("Home", 212, [
            n("Movies", 84, [n("Holiday 2025", 31), n("Kids recitals", 22), n("iMovie Library", 19), n("Other", 12)]),
            n("Photos Library", 52),
            n("Library", 31, [n("Caches", 12), n("Application Support", 11), n("Mail", 8)]),
            n("Documents", 18, [n("Taxes", 6), n("Recipes", 4), n("School", 8)]),
            n("Downloads", 14),
            n("Music", 9),
            n("Desktop", 3),
            n("41 smaller items", 1),
        ])
        m.root = root
        m.path = [root]
        return m
    }

    @MainActor
    static func money() -> MoneyModel {
        let m = MoneyModel()
        m.demo = true
        m.hardware = HardwareInfo(model: "MacBook Air", identifier: "Mac14,2", chip: "Apple M2", memoryGB: 8, appleSilicon: true)
        m.memory = MemoryInfo(total: 8_589_934_592, used: 6_100_000_000, pressure: 2)
        m.health = HealthReport(battery: BatteryInfo(cycles: 412, healthPercent: 88, condition: "Good"), smartOK: true, uptimeDays: 3, thermal: "Cool", cpuSpeedLimit: nil, osVersion: "15.5")
        m.battery = m.health?.battery
        m.subscriptions = [
            SubscriptionApp(name: "Adobe Photoshop", path: "/Applications/Adobe Photoshop.app", vendor: "Adobe Creative Cloud", lastUsed: Date().addingTimeInterval(-171 * 86400), manageURL: "https://account.adobe.com/plans", note: "Photoshop, Lightroom, Acrobat and friends are monthly."),
            SubscriptionApp(name: "Dropbox", path: "/Applications/Dropbox.app", vendor: "Dropbox", lastUsed: Date().addingTimeInterval(-64 * 86400), manageURL: "https://www.dropbox.com/account/plan", note: "Free below 2 GB; the Plus plan is monthly."),
            SubscriptionApp(name: "Microsoft Word", path: "/Applications/Microsoft Word.app", vendor: "Microsoft 365", lastUsed: Date().addingTimeInterval(-2 * 86400), manageURL: "https://account.microsoft.com/services", note: "Office is a yearly plan unless you bought a one-time copy."),
        ]
        m.clouds = [CloudDrive(name: "iCloud Drive", installed: true, running: true, localBytes: 21_000_000_000, folder: nil, manageURL: "x"),
                    CloudDrive(name: "Dropbox", installed: true, running: true, localBytes: 6_400_000_000, folder: nil, manageURL: "https://www.dropbox.com/account/plan"),
                    CloudDrive(name: "Google Drive", installed: true, running: false, localBytes: 900_000_000, folder: nil, manageURL: "https://one.google.com/storage")]
        m.storage = StorageMath(space: DiskSpace(total: 256_000_000_000, free: 19_000_000_000), safeBytes: 4_800_000_000, reviewBytes: 31_000_000_000, icloudLocalBytes: 21_000_000_000)
        m.speedTest = SpeedTest(mbps: 92, latencyMs: 18, bytes: 46_000_000, seconds: 4.1, when: Date())
        m.planMbps = 300
        m.alternatives = [BuiltInAlternative(installedApp: "Adobe Acrobat", path: "/Applications/Adobe Acrobat.app", builtIn: "Preview", note: "Preview fills forms, signs, rotates, merges, and annotates PDFs for free.", open: "/System/Applications/Preview.app")]
        return m
    }

    @MainActor
    static func sorter() -> SorterModel {
        let m = SorterModel()
        m.demo = true
        func mv(_ name: String, _ folder: String, _ cat: String, _ mb: Double) -> SortMove {
            SortMove(from: "/Users/sam/\(folder)/\(name)", to: "/Users/sam/\(folder)/Tidied/\(cat)/\(name)", category: cat, size: Int64(mb * 1_000_000))
        }
        m.moves = [mv("Screenshot 2026-07-03 at 09.12.44.png", "Desktop", "Screenshots", 2.1), mv("Screenshot 2026-07-19 at 16.40.02.png", "Desktop", "Screenshots", 1.7),
                   mv("IMG_4412.jpeg", "Downloads", "Images", 3.4), mv("garden-plan.png", "Desktop", "Images", 0.8),
                   mv("Insurance renewal.pdf", "Downloads", "Documents", 0.4), mv("Recipe - lemon cake.docx", "Desktop", "Documents", 0.1), mv("School newsletter June.pdf", "Downloads", "Documents", 1.2),
                   mv("PhotoEditor-4.2.dmg", "Downloads", "Installers", 410), mv("holiday-photos.zip", "Downloads", "Archives", 890)]
        return m
    }

    @MainActor
    static func menuBar() -> MenuBarModel {
        let m = MenuBarModel()
        m.demo = true
        m.supported = true
        m.apple = MenuBarTidy.items.map { MenuBarItemSetting(key: $0.key, name: $0.name, note: $0.note, visible: ["WiFi", "Sound", "Battery", "Bluetooth"].contains($0.key)) }
        m.spotlight = true
        m.apps = [AppLoad(id: "mb1", name: "Photo Sync", bundlePath: nil, cpu: 0, memory: 120_000_000, processes: 1, isApp: true),
                  AppLoad(id: "mb2", name: "Coupon Finder", bundlePath: nil, cpu: 0, memory: 64_000_000, processes: 1, isApp: true)]
        return m
    }
}

// MARK: - Off-screen rendering

enum Screenshots {
    /// Renders every window with demo data into `dir` as PNGs, then exits.
    @MainActor
    static func render(to dir: String) {
        let out = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        Demo.history()
        let cleanup = Demo.cleanup()
        let speed = Demo.speed()
        UserDefaults.standard.set(false, forKey: ViewOptions.compact)
        UserDefaults.standard.set(true, forKey: ViewOptions.blurbs)
        // The normal main window also opened at launch; close it so our capture windows can be key,
        // otherwise AppKit switches draw in their greyed "inactive window" style.
        for w in NSApp.windows { w.close() }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        for _ in 0..<5 { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }

        let shots: [(String, AnyView, CGSize)] = [
            ("tidy", AnyView(CleanupView(model: cleanup)), CGSize(width: 900, height: 860)),
            ("speed", AnyView(SpeedView(model: speed)), CGSize(width: 900, height: 1180)),
            ("receipts", AnyView(HistoryView()), CGSize(width: 760, height: 520)),
            ("uninstall", AnyView(UninstallView(model: Demo.uninstall())), CGSize(width: 900, height: 600)),
            ("spacemap", AnyView(SpaceMapView(model: Demo.spaceMap())), CGSize(width: 1000, height: 680)),
            ("menubar", AnyView(MenuBarTidyView(model: Demo.menuBar())), CGSize(width: 680, height: 780)),
            ("money", AnyView(MoneyView(model: Demo.money())), CGSize(width: 900, height: 1100)),
            ("sorter", AnyView(SorterView(model: Demo.sorter())), CGSize(width: 760, height: 600)),
        ]
        for (name, view, size) in shots {
            if let png = snapshot(view, size: size, title: "Tidy for Mac") {
                try? png.write(to: out.appendingPathComponent("\(name).png"))
                print("wrote \(name).png")
            }
        }
        Promo.render(into: out, shots: out)
    }

    @MainActor
    static func snapshot(_ view: AnyView, size: CGSize, title: String, chrome: Bool = true) -> Data? {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        let win = CaptureWindow(contentRect: CGRect(origin: .zero, size: size),
                                styleMask: chrome ? [.titled, .closable, .miniaturizable, .resizable] : [.borderless],
                                backing: .buffered, defer: false)
        win.title = title
        win.appearance = NSAppearance(named: .aqua)
        win.contentView = host
        win.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))   // off-screen, never visible
        win.makeKeyAndOrderFront(nil)                            // key window, so controls draw enabled
        win.makeMain()
        // Give SwiftUI a few run-loop turns to lay out lists and lazy stacks.
        for _ in 0..<6 { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        host.layoutSubtreeIfNeeded()
        guard let frame = chrome ? win.contentView?.superview : win.contentView,
              let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return nil }
        frame.cacheDisplay(in: frame.bounds, to: rep)
        win.orderOut(nil)
        return rep.representation(using: .png, properties: [:])
    }
}

/// A process launched from a terminal can't make itself the active app on modern macOS, so its windows
/// never become key and AppKit draws switches and buttons in their greyed inactive style. For the
/// screenshots we tell AppKit the window is key anyway; it only affects how controls are drawn.
final class CaptureWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // The weekly quiet tidy and reminders only run while the app is open: register as a login
        // item once, the first time this version runs. Settings turns it off.
        if !UserDefaults.standard.bool(forKey: "loginItemOffered") {
            UserDefaults.standard.set(true, forKey: "loginItemOffered")
            try? SMAppService.mainApp.register()
        }
        Updates.scheduleBackgroundChecks()
        let args = CommandLine.arguments
        if let i = args.firstIndex(where: { $0 == "--screenshots" || $0 == "screenshots" }), i + 1 < args.count {
            let dir = args[i + 1]
            Task { @MainActor in
                Screenshots.render(to: dir)
                exit(0)
            }
        }
    }
}
