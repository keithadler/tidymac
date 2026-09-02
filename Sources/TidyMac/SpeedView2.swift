//  Speed tab UI, second batch: Wi-Fi and DNS, cloud sync, Time Machine, apps that update
//  themselves, Intel-only apps, menu bar apps and widgets, printers, battery habits, sleep and
//  wake, drive speed.

import SwiftUI

// MARK: - 1. Wi-Fi and DNS

struct NetworkCard: View {
    @Bindable var model: SpeedModel

    var body: some View {
        SpeedCard(title: String(localized: Capabilities.hasWiFi ? "Wi-Fi and internet" : "Internet"), icon: "wifi", color: Tidy.blue,
                  subtitle: String(localized: "A slow connection feels like a slow Mac. This checks the signal, the band you're on, and how quickly names resolve.")) {
            if let n = model.network {
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
                    GridRow {
                        metric("Signal", n.signal.map { "\(n.signalLabel) (\($0) dBm)" } ?? n.signalLabel)
                        metric("Band", n.band ?? "—")
                        metric("Speed to router", n.txRate.map { "\($0) Mbps" } ?? "—")
                    }
                    GridRow {
                        metric("Network", n.ssid ?? "—")
                        metric("Name lookups (DNS)", n.dnsMillis.map { "\($0) ms" } ?? "—")
                        metric("Router response", n.gatewayMillis.map { String(format: "%.0f ms", $0) } ?? "—")
                    }
                }
                .font(.callout)
                VStack(alignment: .leading, spacing: 4) {
                    if n.fasterBandAvailable {
                        tip(.orange, "You're on 2.4 GHz but the same network offers 5 GHz. Forget the network and rejoin, or move closer to the router, to get the faster band.")
                    }
                    if let s = n.signal, s < -70 {
                        tip(.orange, "Weak signal. Moving closer to the router or removing obstacles will help more than anything on the Mac.")
                    }
                    if let d = n.dnsMillis, d > 200 {
                        tip(.orange, "Name lookups are slow. Setting DNS to 1.1.1.1 or 8.8.8.8 in Network settings usually fixes this.")
                    }
                    if let g = n.gatewayMillis, g > 60 {
                        tip(.orange, "The router is slow to answer. Restarting the router often helps.")
                    }
                    if !n.fasterBandAvailable, (n.signal ?? -100) >= -70, (n.dnsMillis ?? 0) <= 200, (n.gatewayMillis ?? 0) <= 60, n.signal != nil {
                        tip(Tidy.green, "Nothing to fix here.")
                    }
                }
                HStack {
                    Button("Open Network settings") { SystemInfo.openSettings("com.apple.Network-Settings.extension") }
                    Button("Check again") { model.refreshNetwork() }.disabled(model.checkingNetwork)
                    if model.checkingNetwork { ProgressView().controlSize(.small) }
                    Spacer()
                }
            } else {
                HStack { ProgressView().controlSize(.small); Text("Checking…").foregroundStyle(.secondary) }
            }
        }
    }

    private func metric(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).fontWeight(.medium)
        }
        .frame(minWidth: 150, alignment: .leading)
    }
}

func tip(_ color: Color, _ text: LocalizedStringKey) -> some View {
    HStack(alignment: .top, spacing: 8) {
        Circle().fill(color).frame(width: 8, height: 8).padding(.top, 6)
        Text(text).font(.callout)
    }
}

// MARK: - 2. Sync stalls

struct SyncCard: View {
    @Bindable var model: SpeedModel

    var body: some View {
        let present = model.sync.filter { $0.running || $0.bundleID.map { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil } ?? true }
        if !present.isEmpty {
            SpeedCard(title: String(localized: "Cloud sync"), icon: "arrow.triangle.2.circlepath.icloud", color: Tidy.teal,
                      subtitle: String(localized: "When iCloud Drive, Dropbox, Google Drive or OneDrive gets stuck on one file it can churn for hours. A restart of the sync app usually clears it.")) {
                ForEach(present) { s in
                    HStack(spacing: 10) {
                        Image(systemName: s.stuck ? "exclamationmark.arrow.triangle.2.circlepath" : (s.running ? "checkmark.icloud" : "icloud.slash"))
                            .foregroundStyle(s.stuck ? Tidy.orange : (s.running ? Tidy.green : .secondary))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.name).fontWeight(.medium)
                            Text(s.stuck ? "Busy for the last 20 seconds straight. Probably stuck." : (s.running ? "Running · \(Int(s.cpuNow))% CPU" : "Not running"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if s.running {
                            Button(s.bundleID == nil ? "Give it a nudge" : "Restart it") { model.restartSync(s) }.controlSize(.small)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }
}

// MARK: - 3. Time Machine

struct TimeMachineCard: View {
    @Bindable var model: SpeedModel

    var body: some View {
        if Capabilities.tmutil {
        SpeedCard(title: String(localized: "Time Machine"), icon: "clock.arrow.circlepath", color: Tidy.purple,
                  subtitle: String(localized: "Backups matter more than speed, but local snapshots can quietly eat the disk when the backup drive has been away for a while.")) {
            if let t = model.timeMachine {
                if !t.configured {
                    tip(Tidy.orange, "Time Machine isn't set up. A cheap external drive is the best insurance a Mac can have.")
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "externaldrive.badge.timemachine").foregroundStyle(Tidy.purple)
                        Text("Backing up to \(t.destination ?? "a drive")").fontWeight(.medium)
                    }
                    if let last = t.lastBackup {
                        let days = Date().timeIntervalSince(last) / 86400
                        tip(days > 7 ? Tidy.orange : Tidy.green, days > 7
                            ? "Last backup was \(Int(days)) days ago. Plug the backup drive in, or check the network drive is reachable."
                            : "Last backup \(last.formatted(.relative(presentation: .named))). Good.")
                    } else {
                        tip(.secondary, "Can't see when the last backup finished. If the drive is plugged in, open Time Machine settings to check.")
                    }
                }
                if !t.localSnapshots.isEmpty {
                    let oldest = t.localSnapshots.first!
                    tip(t.localSnapshots.count > 6 ? Tidy.orange : .secondary,
                        "\(t.localSnapshots.count) local snapshots on the startup disk, oldest \(oldest.formatted(date: .abbreviated, time: .omitted)). macOS trims these itself when space is tight, so they're normally harmless.")
                    if t.localSnapshots.count > 6 {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("To trim them now (needs an administrator), paste this into Terminal:").font(.caption).foregroundStyle(.secondary)
                            Text("sudo tmutil thinlocalsnapshots / 20000000000 4").font(.caption.monospaced()).textSelection(.enabled)
                                .padding(6).background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                HStack {
                    Button("Open Time Machine settings") { SystemInfo.openSettings("com.apple.Time-Machine-Settings.extension") }
                    Spacer()
                }
            } else {
                HStack { ProgressView().controlSize(.small); Text("Checking…").foregroundStyle(.secondary) }
            }
        }
        }
    }
}

// MARK: - 4. App update sweep

struct AppUpdatesCard: View {
    @Bindable var model: SpeedModel
    @State private var showAll = false

    var body: some View {
        SpeedCard(title: String(localized: "Apps that update themselves"), icon: "arrow.triangle.2.circlepath", color: Tidy.orange,
                  subtitle: String(localized: "Apps from outside the App Store each check for updates on their own schedule, and many only when opened. This asks the makers directly where they publish a feed.")) {
            if model.checkingAppUpdates {
                HStack { ProgressView().controlSize(.small); Text("Asking each app's maker…").foregroundStyle(.secondary) }
            } else if let list = model.appUpdates {
                let outdated = list.filter { $0.status == .outdated }
                let unknown = list.filter { $0.status == .unknown }
                if outdated.isEmpty {
                    Label("Everything we could check is current", systemImage: "checkmark.circle.fill").foregroundStyle(Tidy.green)
                }
                ForEach(outdated) { a in
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: a.path)).resizable().frame(width: 22, height: 22)
                        Text(a.name).fontWeight(.medium)
                        Text("\(a.installed) → \(a.latest ?? "?")").font(.caption.monospacedDigit()).foregroundStyle(Tidy.orange)
                        Spacer()
                        Button("Open to update") { NSWorkspace.shared.open(URL(fileURLWithPath: a.path)) }.controlSize(.small)
                    }
                    .padding(.vertical, 2)
                }
                if !unknown.isEmpty {
                    DisclosureGroup(isExpanded: $showAll) {
                        ForEach(unknown) { a in
                            HStack {
                                Text(a.name).font(.callout)
                                Spacer()
                                Text("\(a.installed) · \(a.source)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Text("These don't publish a feed we can read. Open the app and look for Check for Updates in its menu.").font(.caption).foregroundStyle(.secondary)
                    } label: {
                        Text("\(unknown.count) apps check on their own").font(.callout)
                    }
                }
                Text("\(list.filter { $0.status == .appStore }.count) apps come from the App Store and update there.").font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Check app versions") { model.checkAppUpdates() }
            }
        }
    }
}

// MARK: - 5. Rosetta

struct RosettaCard: View {
    @Bindable var model: SpeedModel

    var body: some View {
        if Capabilities.isAppleSilicon {
            SpeedCard(title: String(localized: "Apps built for old Intel Macs"), icon: "cpu", color: Tidy.slate,
                      subtitle: String(localized: "This Mac has an Apple chip. Apps built only for Intel run through a translator called Rosetta: slower, hotter, and harder on the battery. Most have a native version by now.")) {
                if let list = model.rosettaApps {
                    if list.isEmpty {
                        Label("Every app in your Applications folder is native. Nice.", systemImage: "checkmark.circle.fill").foregroundStyle(Tidy.green)
                    } else {
                        ForEach(list) { a in
                            HStack(spacing: 10) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: a.path)).resizable().frame(width: 22, height: 22)
                                Text(a.name).fontWeight(.medium)
                                Spacer()
                                Button("Look for a native version") {
                                    let q = "\(a.name) mac apple silicon download".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                                    NSWorkspace.shared.open(URL(string: "https://duckduckgo.com/?q=\(q)")!)
                                }
                                .controlSize(.small)
                            }
                            .padding(.vertical, 2)
                        }
                        Text("Reinstalling from the maker's site usually gets the native build. App Store apps switch automatically.").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    HStack { ProgressView().controlSize(.small); Text("Reading app binaries…").foregroundStyle(.secondary) }
                }
            }
        }
    }
}

// MARK: - 6. Menu bar and widgets

struct MenuBarCard: View {
    @Bindable var model: SpeedModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        SpeedCard(title: String(localized: "Menu bar apps and widgets"), icon: "menubar.rectangle", color: Tidy.pink,
                  subtitle: String(localized: "Little icons in the menu bar and widgets in Notification Center are full apps that never quit. Each one costs memory all day.")) {
            if !model.menuBarApps.isEmpty {
                Text("In the menu bar").font(.headline)
                ForEach(model.menuBarApps) { app in
                    HStack(spacing: 10) {
                        if let p = app.bundlePath { Image(nsImage: NSWorkspace.shared.icon(forFile: p)).resizable().frame(width: 20, height: 20) }
                        Text(app.name)
                        Spacer()
                        Text(Bytes.string(app.memory)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Button("Quit") { model.quit(app) }.controlSize(.small)
                    }
                    .padding(.vertical, 2)
                }
            }
            if !model.widgets.isEmpty {
                Text("Widgets running now").font(.headline)
                ForEach(model.widgets) { w in
                    HStack {
                        Text(w.name).font(.callout)
                        if !w.isApp { Text("\(w.processes) running · can't be removed, cheap each").font(.caption).foregroundStyle(.tertiary) }
                        Spacer()
                        Text(Bytes.string(w.memory)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 1)
                }
                if model.widgets.contains(where: \.isApp) {
                    Text("Remove third-party widgets by clicking the clock, scrolling to the bottom, and choosing Edit Widgets.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if model.menuBarApps.isEmpty && model.widgets.isEmpty {
                Label("Nothing extra running in the menu bar.", systemImage: "checkmark.circle.fill").foregroundStyle(Tidy.green)
            }
            HStack {
                Button { openWindow(id: "menubar") } label: { Label("Hide or reorder menu bar icons…", systemImage: "menubar.arrow.up.rectangle") }
                Spacer()
            }
        }
    }
}

// MARK: - 7. Printers

struct PrinterCard: View {
    @Bindable var model: SpeedModel

    var body: some View {
        if let list = model.printers, !list.isEmpty {
            SpeedCard(title: String(localized: "Printers"), icon: "printer", color: Tidy.brown,
                      subtitle: String(localized: "Old printers and stuck print jobs slow down every Print dialog. Keep only the printers you actually own.")) {
                ForEach(list) { p in
                    HStack(spacing: 10) {
                        Image(systemName: p.state == "disabled" ? "printer.fill.and.paper.fill" : "printer.fill")
                            .foregroundStyle(p.state == "disabled" || p.state == "paused" ? Tidy.orange : Tidy.green)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(p.name.replacingOccurrences(of: "_", with: " ")).fontWeight(.medium)
                                if p.isDefault { Text("default").font(.caption2).foregroundStyle(.secondary) }
                            }
                            Text("\(p.state)\(p.jobs > 0 ? " · \(p.jobs) jobs waiting" : "")\(p.reason.map { " · \($0)" } ?? "")")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if p.jobs > 0 { Button("Clear jobs") { model.clearPrintJobs(p) }.controlSize(.small) }
                        Button("Remove") { model.removePrinter(p) }.controlSize(.small)
                    }
                    .padding(.vertical, 3)
                }
                HStack {
                    Button("Open Printers & Scanners") { SystemInfo.openSettings("com.apple.Print-Scan-Settings.extension") }
                    Spacer()
                }
            }
        }
    }
}

// MARK: - 8. Battery habits

struct PowerCard: View {
    @Bindable var model: SpeedModel

    var body: some View {
        if let p = model.power, p.percent != nil {
            SpeedCard(title: String(localized: "Battery habits"), icon: "battery.75percent", color: Tidy.green,
                      subtitle: String(localized: "A few settings decide whether the battery lasts three years or five.")) {
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
                    GridRow {
                        metric("Charge", "\(p.percent ?? 0)%" + (p.charging == true ? " · charging" : ""))
                        metric("Power", p.onBattery == true ? String(localized: "On battery") : String(localized: "Plugged in"))
                        metric("Low Power Mode", p.lowPowerMode == true ? String(localized: "On") : String(localized: "Off"))
                    }
                }
                .font(.callout)
                VStack(alignment: .leading, spacing: 4) {
                    if let h = model.health?.battery, let pct = h.healthPercent, pct < 85 {
                        tip(Tidy.orange, "Battery holds \(pct)% of new. Keep it between 20% and 80% when you can, and avoid leaving it at 100% on the charger for days.")
                    }
                    if p.lowPowerMode != true {
                        tip(.secondary, "Low Power Mode on battery stretches a charge by hours for browsing and writing. Turn it on in Battery settings, only on battery.")
                    }
                    tip(.secondary, "Leave Optimised Battery Charging on. It learns your routine and holds at 80% until you need the rest.")
                    if let d = p.displaySleepMinutes, d > 15 {
                        tip(.secondary, "The screen stays on for \(d) minutes when idle. Ten is plenty and saves a lot.")
                    }
                }
                HStack {
                    Button("Open Battery settings") { SystemInfo.openSettings("com.apple.Battery-Settings.extension") }
                    Spacer()
                }
            }
        }
    }

    private func metric(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).fontWeight(.medium)
        }
        .frame(minWidth: 150, alignment: .leading)
    }
}

// MARK: - 9. Sleep and wake

struct SleepCard: View {
    @Bindable var model: SpeedModel

    var body: some View {
        if Capabilities.pmset {
        SpeedCard(title: String(localized: "Sleep and wake"), icon: "moon.zzz.fill", color: Tidy.purple,
                  subtitle: String(localized: "Why the Mac wakes up at night, drains in the bag, or won't sleep at all.")) {
            if let s = model.sleep {
                if !s.assertions.isEmpty {
                    Text("Keeping it awake right now").font(.headline)
                    ForEach(s.assertions) { a in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "eye").foregroundStyle(Tidy.orange).padding(.top, 2)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(a.process).fontWeight(.medium)
                                Text(a.reason ?? a.type).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    Text("Normal while a video plays or a download runs. If something is listed while you're doing nothing, quit it and the Mac will sleep again.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Label("Nothing is stopping the Mac from sleeping.", systemImage: "checkmark.circle.fill").foregroundStyle(Tidy.green)
                }
                if !s.recentWakes.isEmpty {
                    Text("Recent wake-ups").font(.headline)
                    ForEach(s.recentWakes) { w in
                        HStack {
                            Text(w.when).font(.caption.monospaced()).foregroundStyle(.secondary).frame(width: 150, alignment: .leading)
                            Text(w.friendly).font(.callout)
                            Spacer()
                        }
                    }
                }
                if !s.scheduled.isEmpty {
                    Text("Scheduled").font(.headline)
                    ForEach(s.scheduled, id: \.self) { Text($0).font(.caption.monospaced()) }
                }
                Text("Settings that cause wake-ups").font(.headline)
                setting("Wake for network access", s.wakeForNetwork, "Lets other devices wake this Mac. Off unless you share files from it.")
                setting("Power Nap", s.powerNap, "Checks mail and backs up while asleep. Fine plugged in, a drain in a bag.")
                setting("Wake when iPhone or Watch is near", s.proximityWake, "Handy on a desk, wakes the Mac in a bag next to your phone.")
                HStack {
                    Button("Open Battery settings") { SystemInfo.openSettings("com.apple.Battery-Settings.extension") }
                    Button("Energy settings") { SystemInfo.openSettings("com.apple.Energy-Saver-Settings.extension") }
                    Spacer()
                }
            } else {
                HStack { ProgressView().controlSize(.small); Text("Reading the power log…").foregroundStyle(.secondary) }
            }
        }
        }
    }

    private func setting(_ name: LocalizedStringKey, _ on: Bool?, _ note: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: on == true ? "checkmark.circle.fill" : "circle").foregroundStyle(on == true ? Tidy.orange : .secondary).padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                HStack { Text(name).fontWeight(.medium); Text(on == nil ? "" : (on! ? "On" : "Off")).font(.caption).foregroundStyle(.secondary) }
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 10. Disk speed

struct DiskSpeedCard: View {
    @Bindable var model: SpeedModel

    var body: some View {
        SpeedCard(title: String(localized: "How fast are your drives?"), icon: "speedometer", color: Tidy.red,
                  subtitle: String(localized: "A slow drive makes everything on it feel slow. This writes and reads a 256 MB test file, then removes it.")) {
            ForEach(model.volumes) { v in
                HStack(spacing: 10) {
                    Image(systemName: v.isInternal ? "internaldrive" : "externaldrive").foregroundStyle(v.isInternal ? Tidy.blue : Tidy.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(v.name).fontWeight(.medium)
                        if let r = v.readMBs, let w = v.writeMBs {
                            Text("Read \(Int(r)) MB/s · Write \(Int(w)) MB/s · \(v.verdict)").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text(v.isInternal ? "Built-in" : "External").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if model.benchmarking == v.id {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(v.readMBs == nil ? "Test" : "Test again") { model.benchmark(v) }.controlSize(.small).disabled(model.benchmarking != nil)
                    }
                }
                .padding(.vertical, 3)
            }
        }
    }
}
