//  System facts, batch three: the safety check-up, Bluetooth device batteries, default-app
//  handlers, and the quick-fix commands. Quick fixes are limited to actions that need no
//  password and cannot lose data; the one that needs sudo copies a command instead.

import Foundation
import AppKit
import UniformTypeIdentifiers

// MARK: - Types

struct SafetyCheck: Identifiable, Sendable {
    var key: String
    var name: String
    var ok: Bool?            // nil = couldn't tell
    var detail: String
    var fixPane: String?
    var id: String { key }
}

struct DeviceBattery: Identifiable, Sendable {
    var name: String
    var kind: String
    var levels: [(String, Int)]   // ("Left", 85) or ("", 40)
    var id: String { name }
    var lowest: Int? { levels.map(\.1).min() }
}

struct DefaultAppSlot: Identifiable, Sendable {
    var key: String
    var name: String
    var current: String?      // app path
    var candidates: [String]  // app paths
    var id: String { key }
}

struct QuickFix: Identifiable, Sendable {
    var key: String
    var name: String
    var when: String
    var id: String { key }
}

// MARK: - Third batch of system information

enum SystemInfo3 {

    // MARK: Safety check-up

    static func safety() -> [SafetyCheck] {
        var out: [SafetyCheck] = []
        let cannot = String(localized: "Can't be checked on this Mac.")

        let fv = Capabilities.fdesetup ? SystemInfo.run("/usr/bin/fdesetup", ["status"], timeout: 10) : ""
        out.append(SafetyCheck(key: "filevault", name: String(localized: "Disk encryption (FileVault)"),
                               ok: fv.isEmpty ? nil : fv.contains("FileVault is On"),
                               detail: fv.isEmpty ? cannot : fv.contains("FileVault is On")
                                   ? String(localized: "On. If the Mac is lost, nobody can read what's on it.")
                                   : String(localized: "Off. Anyone with the Mac can read every file. Turning it on is free and invisible day to day."),
                               fixPane: "com.apple.settings.PrivacySecurity.extension?Privacy_FileVault"))

        let fw = Capabilities.firewall ? SystemInfo.run("/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate"], timeout: 10) : ""
        let fwOn = fw.contains("enabled")
        out.append(SafetyCheck(key: "firewall", name: String(localized: "Firewall"), ok: fw.isEmpty ? nil : fwOn,
                               detail: fw.isEmpty ? cannot : fwOn ? String(localized: "On. Blocks unexpected incoming connections.")
                                            : String(localized: "Off. Worth turning on, especially on public Wi-Fi."),
                               fixPane: "com.apple.Network-Settings.extension?Firewall"))

        let su = SystemInfo.run("/usr/bin/defaults", ["read", "/Library/Preferences/com.apple.SoftwareUpdate"], timeout: 10)
        func flag(_ k: String) -> Bool? {
            guard let line = su.split(separator: "\n").first(where: { $0.contains(k) }) else { return nil }
            return line.contains("= 1")
        }
        let check = flag("AutomaticCheckEnabled"), install = flag("AutomaticallyInstallMacOSUpdates"), critical = flag("CriticalUpdateInstall")
        let autoOK = (check ?? true) && (critical ?? true)
        out.append(SafetyCheck(key: "updates", name: String(localized: "Automatic updates"), ok: su.isEmpty ? nil : autoOK,
                               detail: su.isEmpty ? cannot : autoOK
                                   ? (install == true ? String(localized: "On, including macOS updates. Security fixes arrive on their own.")
                                                      : String(localized: "Security fixes install on their own. Full macOS updates wait for you, which is fine."))
                                   : String(localized: "Off. Security fixes won't arrive unless someone remembers. Turn on at least the security responses."),
                               fixPane: "com.apple.Software-Update-Settings.extension"))

        // sysadminctl prints its answer on stderr, so read both streams.
        var lockText = ""
        if Capabilities.sysadminctl {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/sysadminctl"); p.arguments = ["-screenLock", "status"]
            let errPipe = Pipe(), outPipe = Pipe(); p.standardError = errPipe; p.standardOutput = outPipe
            if (try? p.run()) != nil {
                p.waitUntilExit()
                lockText = String(decoding: outPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    + String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            }
        }
        let lockOff = lockText.lowercased().contains("screenlock is off")
        var lockDetail = String(localized: "Asks for the password soon after the screen sleeps.")
        if let m = lockText.range(of: #"(\d+) seconds"#, options: .regularExpression), let secs = Int(lockText[m].split(separator: " ").first ?? "") {
            lockDetail = secs <= 300 ? String(localized: "Asks for the password within \(secs / 60 == 0 ? secs : secs / 60) \(secs < 60 ? "seconds" : "minutes") of the screen sleeping. Good.")
                                     : String(localized: "Waits \(secs / 60) minutes before asking for the password. Five minutes or less is safer.")
        }
        out.append(SafetyCheck(key: "lock", name: String(localized: "Lock when the screen sleeps"), ok: lockText.isEmpty ? nil : !lockOff,
                               detail: lockText.isEmpty ? cannot : lockOff ? String(localized: "Off. Anyone who walks up to the sleeping Mac is in.") : lockDetail,
                               fixPane: "com.apple.Lock-Screen-Settings.extension"))

        let gk = Capabilities.spctl ? SystemInfo.run("/usr/sbin/spctl", ["--status"], timeout: 10) : ""
        out.append(SafetyCheck(key: "gatekeeper", name: String(localized: "App checking (Gatekeeper)"), ok: gk.isEmpty ? nil : gk.contains("enabled"),
                               detail: gk.isEmpty ? cannot : gk.contains("enabled") ? String(localized: "On. Apps from unknown makers get checked before they open.")
                                                              : String(localized: "Off. Any downloaded app can run without a check."),
                               fixPane: "com.apple.settings.PrivacySecurity.extension"))
        return out
    }

    // MARK: Device batteries

    static func deviceBatteries() -> [DeviceBattery] {
        let json = SystemInfo.run("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"], timeout: 20)
        guard let data = json.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = obj["SPBluetoothDataType"] as? [[String: Any]] else { return [] }
        var out: [DeviceBattery] = []
        for controller in items {
            for devs in (controller["device_connected"] as? [[String: Any]]) ?? [] {
                for (name, v) in devs {
                    guard let d = v as? [String: Any] else { continue }
                    var levels: [(String, Int)] = []
                    let map: [(String, String)] = [("device_batteryLevelMain", ""), ("device_batteryLevelLeft", String(localized: "Left")),
                                                   ("device_batteryLevelRight", String(localized: "Right")), ("device_batteryLevelCase", String(localized: "Case"))]
                    for (k, label) in map {
                        if let s = d[k] as? String, let n = Int(s.filter(\.isNumber)) { levels.append((label, n)) }
                    }
                    guard !levels.isEmpty else { continue }
                    let kind = (d["device_minorType"] as? String) ?? (d["device_productName"] as? String) ?? ""
                    out.append(DeviceBattery(name: name, kind: kind, levels: levels))
                }
            }
        }
        return out.sorted { ($0.lowest ?? 100) < ($1.lowest ?? 100) }
    }

    // MARK: Default apps

    @MainActor
    static func defaultApps() -> [DefaultAppSlot] {
        let ws = NSWorkspace.shared
        func slot(_ key: String, _ name: String, url: URL?, type: UTType?) -> DefaultAppSlot {
            var current: String?
            var cands: [URL] = []
            if let url {
                current = ws.urlForApplication(toOpen: url)?.path
                cands = ws.urlsForApplications(toOpen: url)
            } else if let type {
                current = ws.urlForApplication(toOpen: type)?.path
                cands = ws.urlsForApplications(toOpen: type)
            }
            let paths = Array(Set(cands.map(\.path))).filter { !$0.contains("/Contents/") }.sorted { URL(fileURLWithPath: $0).lastPathComponent.localizedCaseInsensitiveCompare(URL(fileURLWithPath: $1).lastPathComponent) == .orderedAscending }
            return DefaultAppSlot(key: key, name: name, current: current, candidates: paths)
        }
        return [
            slot("http", String(localized: "Web links"), url: URL(string: "https://example.com"), type: nil),
            slot("mailto", String(localized: "Email links"), url: URL(string: "mailto:someone@example.com"), type: nil),
            slot("pdf", String(localized: "PDF files"), url: nil, type: .pdf),
            slot("image", String(localized: "Photos and images (JPEG)"), url: nil, type: .jpeg),
            slot("text", String(localized: "Plain text files"), url: nil, type: .plainText),
        ]
    }

    @MainActor
    static func setDefault(_ slot: DefaultAppSlot, to appPath: String, done: @escaping (String?) -> Void) {
        let app = URL(fileURLWithPath: appPath)
        let handler: (Error?) -> Void = { e in Task { @MainActor in done(e?.localizedDescription) } }
        switch slot.key {
        case "http": NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: "http", completion: handler)
        case "mailto": NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: "mailto", completion: handler)
        case "pdf": NSWorkspace.shared.setDefaultApplication(at: app, toOpen: .pdf, completion: handler)
        case "image": NSWorkspace.shared.setDefaultApplication(at: app, toOpen: .jpeg, completion: handler)
        case "text": NSWorkspace.shared.setDefaultApplication(at: app, toOpen: .plainText, completion: handler)
        default: done(nil)
        }
    }

    // MARK: Quick fixes

    /// Only the fixes whose tool exists on this Mac. Finder, Dock and the menu bar always do.
    static var availableFixes: [QuickFix] {
        fixes.filter { f in
            switch f.key {
            case "openwith": return Capabilities.lsregister
            case "dns": return Capabilities.dscacheutil
            case "quicklook": return Capabilities.qlmanage
            case "spotlight": return Capabilities.mdls
            default: return true
            }
        }
    }

    static let fixes: [QuickFix] = [
        QuickFix(key: "finder", name: String(localized: "Restart Finder"), when: String(localized: "Desktop icons odd, windows not responding, files not showing up.")),
        QuickFix(key: "dock", name: String(localized: "Restart the Dock"), when: String(localized: "Dock frozen, Mission Control or app switching acting up.")),
        QuickFix(key: "menubar", name: String(localized: "Restart the menu bar"), when: String(localized: "Icons missing, clock stuck, Control Center not opening.")),
        QuickFix(key: "openwith", name: String(localized: "Rebuild the Open With menu"), when: String(localized: "Duplicate or deleted apps still listed under Open With.")),
        QuickFix(key: "dns", name: String(localized: "Flush the DNS cache"), when: String(localized: "Websites won't load after changing Wi-Fi or VPN, though others do.")),
        QuickFix(key: "quicklook", name: String(localized: "Reset file previews"), when: String(localized: "Space-bar previews blank, wrong, or slow.")),
        QuickFix(key: "spotlight", name: String(localized: "Rebuild the Spotlight index"), when: String(localized: "Search can't find files that exist. Needs an administrator, so this copies the command for you.")),
    ]

    /// Runs a fix. Returns a message for the user, or nil when a command is copied instead.
    static func run(_ fix: QuickFix) -> String {
        switch fix.key {
        case "finder":
            _ = SystemInfo.run("/usr/bin/killall", ["Finder"], timeout: 5)
            return String(localized: "Finder restarted.")
        case "dock":
            _ = SystemInfo.run("/usr/bin/killall", ["Dock"], timeout: 5)
            return String(localized: "Dock restarted.")
        case "menubar":
            _ = SystemInfo.run("/usr/bin/killall", ["ControlCenter", "SystemUIServer"], timeout: 5)
            return String(localized: "Menu bar restarted.")
        case "openwith":
            _ = SystemInfo.run("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
                               ["-kill", "-r", "-domain", "local", "-domain", "system", "-domain", "user"], timeout: 120)
            _ = SystemInfo.run("/usr/bin/killall", ["Finder"], timeout: 5)
            return String(localized: "Open With menu rebuilt. Finder restarted to pick it up.")
        case "dns":
            _ = SystemInfo.run("/usr/bin/dscacheutil", ["-flushcache"], timeout: 10)
            return String(localized: "DNS cache flushed. If a site still won't load, turn Wi-Fi off and on.")
        case "quicklook":
            _ = SystemInfo.run("/usr/bin/qlmanage", ["-r"], timeout: 15)
            _ = SystemInfo.run("/usr/bin/qlmanage", ["-r", "cache"], timeout: 15)
            return String(localized: "Previews reset.")
        case "spotlight":
            let cmd = "sudo mdutil -E /"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(cmd, forType: .string)
            return String(localized: "Copied “\(cmd)” to the clipboard. Open Terminal, paste it, press Return, and enter your password. Search will be slow for an hour while it rebuilds.")
        default:
            return ""
        }
    }
}
