//  The monthly checkup report: one page with the health verdict, what a tidy would free, the money
//  findings, and what was done recently. Written as HTML (and Markdown for the command line) so it
//  can be handed to whoever does the family's tech support.

import Foundation
import AppKit

struct ReportData: Sendable {
    var date = Date()
    var space: DiskSpace?
    var memory: MemoryInfo?
    var health: HealthReport?
    var findings: [(level: String, title: String, detail: String)] = []
    var verdict = "green"
    var safety: [SafetyCheck] = []
    var categories: [CleanCategory] = []
    var subscriptions: [SubscriptionApp] = []
    var clouds: [CloudDrive] = []
    var hardware: HardwareInfo?
    var macVerdict: MacVerdict?
    var battery: (level: Verdict, text: String)?
    var sessions: [TidySession] = []
    var hostName = Host.current().localizedName ?? "this Mac"
}

enum Report {

    /// Gathers everything on the main actor so the SpeedModel verdict logic is reused as-is.
    @MainActor
    static func gather() -> ReportData {
        var r = ReportData()
        let procs = SystemInfo.processes()
        let m = SpeedModel(); m.demo = true
        m.space = DiskSpace.current(); m.memory = SystemInfo.memory(); m.uptimeDays = SystemInfo.uptimeDays
        m.apps = SystemInfo.appLoads(procs)
        m.health = SystemInfo.health()
        m.safety = SystemInfo3.safety()
        m.agents = SystemInfo.agents(procs)
        r.space = m.space; r.memory = m.memory; r.health = m.health; r.safety = m.safety ?? []
        r.findings = m.findings.map { ($0.level == .act ? "red" : "yellow", $0.title, $0.detail) }
        r.verdict = m.verdict == .good ? "green" : (m.verdict == .watch ? "yellow" : "red")
        r.categories = [CleanKind.caches, .logs, .installers, .devCaches, .claude, .leftovers, .unusedApps, .iosBackups, .bigFiles].map { Scanner.scan($0) }.filter { !$0.items.isEmpty }
        r.subscriptions = MoneyInfo.subscriptions()
        r.clouds = MoneyInfo.cloudDrives()
        let hw = MoneyInfo.hardware()
        r.hardware = hw
        r.macVerdict = MoneyInfo.macVerdict(hw: hw, health: m.health, memory: m.memory, space: m.space)
        r.battery = MoneyInfo.batteryDecision(m.health?.battery)
        r.sessions = History.shared.sessions.filter { $0.date > Date().addingTimeInterval(-30 * 86400) }
        return r
    }

    static func markdown(_ r: ReportData) -> String {
        var s = "# Tidy for Mac checkup — \(r.hostName)\n\n_\(r.date.formatted(date: .long, time: .shortened))_\n\n"
        let dot = r.verdict == "green" ? "🟢" : (r.verdict == "yellow" ? "🟡" : "🔴")
        s += "## \(dot) Health: \(r.verdict)\n\n"
        if r.findings.isEmpty { s += "Nothing needs attention.\n\n" }
        for f in r.findings { s += "- **\(f.title)** — \(f.detail)\n" }
        if let sp = r.space, let mem = r.memory {
            s += "\nFree space **\(Bytes.string(sp.free))** of \(Bytes.string(sp.total)) · Memory \(Bytes.string(mem.used)) of \(Bytes.string(mem.total)) (\(mem.pressureLabel))"
            if let h = r.health { s += " · Temperature \(h.thermal)"; if let b = h.battery { s += " · Battery \(b.healthPercent ?? 0)%, \(b.cycles ?? 0) cycles" } }
            s += "\n\n"
        }
        if !r.safety.isEmpty {
            s += "## Safety\n\n"
            for c in r.safety { s += "- \(c.ok == true ? "✅" : (c.ok == false ? "⚠️" : "❔")) **\(c.name)** — \(c.detail)\n" }
            s += "\n"
        }
        s += "## What a tidy would free\n\n"
        let safe = r.categories.filter { $0.kind.safety == .safe || $0.kind.safety == .mixed }.reduce(0) { $0 + $1.selectedTotal }
        let review = r.categories.filter { $0.kind.safety == .review }.reduce(0) { $0 + $1.total }
        s += "Safe to clear now: **\(Bytes.string(safe))**. Worth a look: **\(Bytes.string(review))**.\n\n"
        for c in r.categories { s += "- \(c.kind.title): \(Bytes.string(c.total)) in \(c.items.count) items (\(c.kind.safety.label))\n" }
        s += "\n## Money\n\n"
        if let v = r.macVerdict { s += "**\(v.headline)** \(v.cheapestFix)\n\n"; for x in v.reasons { s += "- \(x)\n" }; s += "\n" }
        if let b = r.battery { s += "Battery: \(b.text)\n\n" }
        let idle = r.subscriptions.filter { ($0.daysIdle ?? 9999) >= 60 }
        if !idle.isEmpty {
            s += "Subscription apps not opened in 60+ days (cancel if you're paying):\n\n"
            for x in idle { s += "- \(x.vendor) — \(x.lastUsed == nil ? "never opened" : "last opened \(x.lastUsed!.formatted(date: .abbreviated, time: .omitted))")\n" }
            s += "\n"
        }
        let active = r.clouds.filter(\.installed)
        if active.count >= 2 { s += "\(active.count) cloud drives installed (\(active.map(\.name).joined(separator: ", "))). One is usually enough.\n\n" }
        s += "## Done in the last 30 days\n\n"
        if r.sessions.isEmpty { s += "Nothing yet.\n" }
        for x in r.sessions { s += "- \(x.date.formatted(date: .abbreviated, time: .shortened)) · \(x.label ?? (x.automatic ? "quiet tidy" : "tidy up")) · \(x.movedCount) items · \(Bytes.string(x.totalSize))\n" }
        s += "\n---\n_Made by Tidy for Mac. Nothing in this report was changed on the Mac; everything Tidy moves goes to the Trash with a receipt._\n"
        return s
    }

    /// A small, dependency-free Markdown-to-HTML for the report's own limited syntax.
    static func html(_ r: ReportData) -> String {
        func esc(_ s: String) -> String { s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") }
        func inline(_ s: String) -> String {
            var t = esc(s)
            while let a = t.range(of: "**"), let b = t[a.upperBound...].range(of: "**") {
                t.replaceSubrange(a.lowerBound..<b.upperBound, with: "<strong>" + t[a.upperBound..<b.lowerBound] + "</strong>")
            }
            if t.hasPrefix("_") && t.hasSuffix("_") { t = "<em>" + t.dropFirst().dropLast() + "</em>" }
            return t
        }
        var body = ""
        var inList = false
        for line in markdown(r).split(separator: "\n", omittingEmptySubsequences: false) {
            let l = String(line)
            if l.hasPrefix("- ") { if !inList { body += "<ul>"; inList = true }; body += "<li>\(inline(String(l.dropFirst(2))))</li>"; continue }
            if inList { body += "</ul>"; inList = false }
            if l.hasPrefix("# ") { body += "<h1>\(inline(String(l.dropFirst(2))))</h1>" }
            else if l.hasPrefix("## ") { body += "<h2>\(inline(String(l.dropFirst(3))))</h2>" }
            else if l == "---" { body += "<hr>" }
            else if !l.isEmpty { body += "<p>\(inline(l))</p>" }
        }
        if inList { body += "</ul>" }
        let color = r.verdict == "green" ? "#2aa860" : (r.verdict == "yellow" ? "#f29429" : "#e04c4c")
        return """
        <!doctype html><html><head><meta charset="utf-8"><title>Tidy for Mac checkup</title>
        <style>body{font:15px/1.5 -apple-system,Helvetica,Arial,sans-serif;max-width:760px;margin:40px auto;padding:0 20px;color:#222}
        h1{font-size:26px}h2{font-size:19px;margin-top:28px;border-bottom:1px solid #eee;padding-bottom:4px}
        h2:first-of-type{color:\(color)}ul{padding-left:20px}li{margin:4px 0}hr{border:0;border-top:1px solid #eee;margin:30px 0}em{color:#777}</style>
        </head><body>\(body)</body></html>
        """
    }

    /// Writes the report and returns the file, so the caller can open or share it.
    static func write(_ r: ReportData, to url: URL, html: Bool) throws {
        try (html ? self.html(r) : markdown(r)).write(to: url, atomically: true, encoding: .utf8)
    }
}
