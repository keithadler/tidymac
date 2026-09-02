//  Speed tab UI, first batch of cards: verdict, what's running now, startup items, browser
//  weight, storage tricks, macOS updates, lighter look. SpeedCard is the shared card chrome
//  used by every Speed card in this file and the two that follow it.

import SwiftUI

struct SpeedView: View {
    @Bindable var model: SpeedModel
    @AppStorage(ViewOptions.compact) private var compact = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: compact ? 8 : 14) {
                    VerdictCard(model: model)
                    SafetyCard(model: model)
                    QuickFixCard(model: model)
                    RightNowCard(model: model)
                    StartupCard(model: model)
                    MenuBarCard(model: model)
                    BrowserCard(model: model)
                    NetworkCard(model: model)
                    SyncCard(model: model)
                    StorageCard()
                    DiskSpeedCard(model: model)
                    TimeMachineCard(model: model)
                    UpdatesCard(model: model)
                    AppUpdatesCard(model: model)
                    RosettaCard(model: model)
                    PowerCard(model: model)
                    DeviceBatteryCard(model: model)
                    DefaultAppsCard(model: model)
                    SleepCard(model: model)
                    PrinterCard(model: model)
                    LighterLookCard(model: model)
                }
                .padding(compact ? 12 : 20)
            }
            if let m = model.message {
                Divider()
                HStack {
                    Image(systemName: "info.circle").foregroundStyle(Tidy.blue)
                    Text(m).font(.callout)
                    Spacer()
                    Button("OK") { model.message = nil }.controlSize(.small)
                }
                .padding(.horizontal, 20).padding(.vertical, 10).background(.bar)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { model.refreshSlow(); model.refreshNow() } label: { Label("Check again", systemImage: "arrow.clockwise") }
                    .disabled(model.loadingSlow)
            }
        }
        .onAppear { model.startLive() }
        .onDisappear { model.stopLive() }
    }
}

// MARK: - Shared card chrome

struct SpeedCard<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    var subtitle: String? = nil
    @ViewBuilder var content: Content
    @AppStorage(ViewOptions.compact) private var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(color.opacity(0.18)).frame(width: compact ? 28 : 40, height: compact ? 28 : 40)
                    Image(systemName: icon).font(compact ? .body : .title3).foregroundStyle(color)
                }
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(compact ? .headline : .title3.weight(.semibold))
                    if let subtitle, !compact { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
                }
                Spacer()
            }
            content
        }
        .padding(compact ? 10 : 16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.06)))
    }
}

func verdictColor(_ v: Verdict) -> Color {
    switch v { case .good: return Tidy.green; case .watch: return Tidy.orange; case .act: return Tidy.red }
}

// MARK: - 10. Health verdict

struct VerdictCard: View {
    @Bindable var model: SpeedModel

    private var headline: String {
        switch model.verdict {
        case .good:  return String(localized: "Your Mac is in good shape")
        case .watch: return String(localized: "A few things worth a look")
        case .act:   return String(localized: "Something needs attention")
        }
    }

    var body: some View {
        let color = verdictColor(model.verdict)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(color.opacity(0.18)).frame(width: 64, height: 64)
                    Image(systemName: model.verdict == .good ? "checkmark" : (model.verdict == .watch ? "exclamationmark" : "exclamationmark.triangle.fill"))
                        .font(.system(size: 28, weight: .bold)).foregroundStyle(color)
                }
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(headline).font(.title2.weight(.bold))
                    if model.health == nil {
                        HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("Checking battery, drive, and temperature…").foregroundStyle(.secondary) }
                    } else if model.findings.isEmpty {
                        Text("Nothing to do. Come back in a month.").foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            if !model.findings.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.findings) { f in
                        HStack(alignment: .top, spacing: 8) {
                            Circle().fill(verdictColor(f.level)).frame(width: 8, height: 8).padding(.top, 6)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(f.title).fontWeight(.semibold)
                                Text(f.detail).font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if let h = model.health {
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
                    GridRow {
                        metric("Free space", model.space.map { Bytes.string($0.free) } ?? "—")
                        metric("Memory", model.memory.map { "\(Bytes.string($0.used)) of \(Bytes.string($0.total)) · \($0.pressureLabel)" } ?? "—")
                        metric("Temperature", h.thermal + (h.cpuSpeedLimit.map { $0 < 100 ? " · \($0)% speed" : "" } ?? ""))
                    }
                    GridRow {
                        metric("Drive", h.smartOK.map { $0 ? String(localized: "Healthy") : String(localized: "Reports a problem") } ?? String(localized: "Not reported"))
                        metric("Battery", h.battery.map { b in
                            [b.healthPercent.map { "\($0)%" }, b.cycles.map { String(localized: "\($0) cycles") }, b.condition].compactMap { $0 }.joined(separator: " · ")
                        } ?? String(localized: "No battery"))
                        metric("Since restart", h.uptimeDays < 1 ? String(localized: "Today") : String(localized: "\(Int(h.uptimeDays)) days"))
                    }
                }
                .font(.callout)
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(color.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(color.opacity(0.35)))
    }

    private func metric(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).fontWeight(.medium)
        }
        .frame(minWidth: 160, alignment: .leading)
    }
}

// MARK: - 2, 6, 7. Right now

struct RightNowCard: View {
    @Bindable var model: SpeedModel
    @State private var showAll = false

    var body: some View {
        SpeedCard(title: String(localized: "What's using your Mac right now"), icon: "gauge.with.dots.needle.67percent", color: Tidy.blue,
                  subtitle: String(localized: "The apps taking the most memory and processor. Quitting one you're not using is the fastest speed-up there is.")) {
            if let m = model.memory {
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08))
                            RoundedRectangle(cornerRadius: 6).fill((m.pressure >= 4 ? Tidy.red : m.pressure >= 2 ? Tidy.orange : Tidy.green).gradient)
                                .frame(width: max(6, geo.size.width * m.usedFraction))
                        }
                    }
                    .frame(height: 10)
                    Text("Memory: \(Bytes.string(m.used)) of \(Bytes.string(m.total)) in use · \(m.pressureLabel)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            if let bg = model.background {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "hourglass").foregroundStyle(Tidy.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(bg).fontWeight(.semibold)
                        Text("That's why the fan may be on. It finishes on its own, usually within the hour. Nothing to do.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(10).background(Tidy.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
            if model.uptimeDays >= 14 {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise.circle").foregroundStyle(Tidy.purple)
                    Text("It's been \(Int(model.uptimeDays)) days since the last restart. A restart is the classic fix for a sluggish Mac.")
                        .font(.callout)
                    Spacer()
                    Button("Restart now…") { model.restart() }.controlSize(.small)
                        .help("Asks macOS to restart. You'll be asked to save any open work.")
                }
                .padding(10).background(Tidy.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            let shown = model.apps.filter(\.isApp).prefix(showAll ? 25 : 8)
            VStack(spacing: 0) {
                ForEach(Array(shown)) { app in
                    HStack(spacing: 10) {
                        if let p = app.bundlePath {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: p)).resizable().frame(width: 22, height: 22).accessibilityHidden(true)
                        }
                        Text(app.name).lineLimit(1)
                        if app.cpu >= 80 { Text("busy").font(.caption2.weight(.semibold)).padding(.horizontal, 5).padding(.vertical, 1).background(Tidy.red.opacity(0.15), in: Capsule()).foregroundStyle(Tidy.red) }
                        Spacer()
                        Text("\(Int(app.cpu))% CPU").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 70, alignment: .trailing)
                        Text(Bytes.string(app.memory)).font(.callout.monospacedDigit()).frame(width: 84, alignment: .trailing)
                        if app.bundlePath != Bundle.main.bundleURL.path {
                            Menu {
                                Button("Quit") { model.quit(app) }
                                Button("Force Quit") { model.quit(app, force: true) }
                            } label: { Text("Quit") }
                            .menuStyle(.borderlessButton).frame(width: 60)
                            .accessibilityLabel(Text("Quit \(app.name)"))
                        } else {
                            Text("this app").font(.caption).foregroundStyle(.tertiary).frame(width: 60)
                        }
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }
            if model.apps.filter(\.isApp).count > 8 {
                Button(showAll ? "Show fewer" : "Show more") { showAll.toggle() }.buttonStyle(.link).font(.callout)
            }
        }
    }
}

// MARK: - 1. Startup

struct StartupCard: View {
    @Bindable var model: SpeedModel
    @State private var showSystem = false

    var body: some View {
        SpeedCard(title: String(localized: "Things that start with your Mac"), icon: "power.circle.fill", color: Tidy.green,
                  subtitle: String(localized: "Every one of these runs at login whether you use it or not. Turning off ones you don't need makes startup and everything after it faster.")) {
            if let e = model.loginItemsError {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "hand.raised.fill").foregroundStyle(Tidy.orange)
                    Text(e).font(.callout)
                    Spacer()
                    Button("Allow") { SystemInfo.openSettings(Capabilities.automationPane) }.controlSize(.small)
                }
                .padding(10).background(Tidy.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
            if let b = model.boot, b.bootToLoginSeconds != nil || b.loginToReadySeconds != nil {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 14) {
                        if let s = b.bootToLoginSeconds { Text("Power on → login: \(Int(s)) s").fontWeight(.medium) }
                        if let s = b.loginToReadySeconds { Text("Login → everything running: \(Int(s)) s").fontWeight(.medium) }
                    }
                    if let slow = b.items.first, slow.secondsAfterLogin > 15 {
                        Text("\(slow.name) was the last to start, \(Int(slow.secondsAfterLogin)) seconds after login. Turning off what you don't need below shortens every morning.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(10).background(Tidy.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            if !model.loginItems.isEmpty {
                Text("Open at login").font(.headline)
                ForEach(model.loginItems) { li in
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: li.path)).resizable().frame(width: 22, height: 22).accessibilityHidden(true)
                        Text(li.name)
                        Spacer()
                        Button("Don't open at login") { model.removeLoginItem(li) }.controlSize(.small)
                    }
                    .padding(.vertical, 3)
                }
                Divider()
            }
            let user = model.agents.filter { !$0.system }
            if !user.isEmpty {
                Text("Background helpers").font(.headline)
                ForEach(user) { a in
                    HStack(spacing: 10) {
                        Toggle("", isOn: Binding(get: { !a.disabledByTidy }, set: { _ in model.toggleAgent(a) }))
                            .toggleStyle(.switch).labelsHidden().controlSize(.small)
                            .accessibilityLabel(Text("\(a.vendor) background helper"))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(a.vendor).fontWeight(.medium)
                            Text(a.label).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if a.disabledByTidy {
                            Text("Off").font(.caption).foregroundStyle(.secondary)
                        } else if a.memory > 0 {
                            Text("\(Bytes.string(a.memory)) · \(Int(a.cpu))% CPU").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        } else {
                            Text(a.loaded ? String(localized: "idle") : String(localized: "not running")).font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
            let sys = model.agents.filter(\.system)
            if !sys.isEmpty {
                DisclosureGroup(isExpanded: $showSystem) {
                    ForEach(sys) { a in
                        HStack {
                            Text(a.vendor).fontWeight(.medium)
                            Text(a.label).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                            Spacer()
                            if a.memory > 0 { Text(Bytes.string(a.memory)).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                        }
                        .padding(.vertical, 2)
                    }
                    Text("These were installed for everyone on this Mac and need an administrator to change. Usually they belong to work or school management, printers, or security software.")
                        .font(.caption).foregroundStyle(.secondary)
                } label: {
                    Text("\(sys.count) helpers installed for all users").font(.callout)
                }
            }
            HStack {
                Button("Open Login Items settings") { SystemInfo.openSettings("com.apple.LoginItems-Settings.extension") }
                Spacer()
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - 3. Browser weight

struct BrowserCard: View {
    @Bindable var model: SpeedModel

    var body: some View {
        if !model.browsers.isEmpty {
            SpeedCard(title: String(localized: "Browser weight"), icon: "globe", color: Tidy.teal,
                      subtitle: String(localized: "Browsers keep gigabytes of site data and every extension costs memory on every page. Clearing site data keeps you signed in; sites just load fresh once.")) {
                ForEach(model.browsers) { b in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(b.name).font(.headline)
                            if b.running { Text("open").font(.caption2.weight(.semibold)).padding(.horizontal, 5).padding(.vertical, 1).background(Tidy.blue.opacity(0.15), in: Capsule()).foregroundStyle(Tidy.blue) }
                            Spacer()
                            Text("\(Bytes.string(b.total)) of site data").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                            Button("Clear site data") { model.clearBrowserCaches(b) }.controlSize(.small).disabled(b.running || b.total == 0)
                                .help(b.running ? "Quit \(b.name) first" : "Moves cached site files to the Trash")
                            Button("Manage extensions") { model.manageExtensions(b) }.controlSize(.small)
                        }
                        ForEach(b.profiles) { p in
                            HStack {
                                Text(p.name).font(.callout)
                                Spacer()
                                Text(Bytes.string(p.siteData)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            .padding(.leading, 12)
                        }
                        if !b.extensions.isEmpty {
                            DisclosureGroup("\(b.extensions.count) extensions") {
                                ForEach(b.extensions) { e in
                                    HStack {
                                        Text(e.name).font(.callout).lineLimit(1)
                                        Text(e.profile).font(.caption).foregroundStyle(.tertiary)
                                        Spacer()
                                        Text(Bytes.string(e.size)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 1)
                                }
                            }
                            .font(.callout)
                        }
                    }
                    if b.id != model.browsers.last?.id { Divider() }
                }
                Text("Safari keeps its data where only System Settings can reach it: Safari > Settings > Privacy > Manage Website Data.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 4, 5. Storage tricks

struct StorageCard: View {
    private var purgeable: Int64? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let strict = v.volumeAvailableCapacity, let important = v.volumeAvailableCapacityForImportantUsage else { return nil }
        return max(0, important - Int64(strict))
    }

    var body: some View {
        SpeedCard(title: String(localized: "Space macOS can free on its own"), icon: "icloud.and.arrow.up", color: Tidy.purple,
                  subtitle: String(localized: "macOS gets sluggish under about 10% free. These built-in switches keep space free without you doing anything.")) {
            if let s = DiskSpace.current() {
                let freeFrac = 1 - s.usedFraction
                HStack(spacing: 8) {
                    Image(systemName: freeFrac < 0.1 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(freeFrac < 0.1 ? Tidy.red : Tidy.green)
                    Text(freeFrac < 0.1
                         ? "Only \(Int(freeFrac * 100))% free. Below the 10% line, so use Tidy Up first."
                         : "\(Int(freeFrac * 100))% free. Above the 10% line macOS needs to run well.")
                        .font(.callout)
                    Spacer()
                }
            }
            if let p = purgeable, p > 100_000_000 {
                Text("macOS is already holding \(Bytes.string(p)) it can reclaim automatically when needed. That's counted as free space in Finder, so no action needed.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                row("Optimise Mac Storage", "Keeps only recent iCloud Drive files on this Mac and fetches older ones when opened.", "com.apple.systempreferences.AppleIDSettings:icloud")
                row("Empty Trash automatically", "Removes anything that has sat in the Trash for 30 days.", "com.apple.settings.Storage")
                row("Download only recent Mail attachments", "In Mail > Settings > Accounts, stops old attachments filling the disk.", nil)
            }
        }
    }

    private func row(_ title: LocalizedStringKey, _ detail: LocalizedStringKey, _ pane: String?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "switch.2").foregroundStyle(Tidy.purple).padding(.top, 2).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let pane {
                Button("Open") { SystemInfo.openSettings(pane) }.controlSize(.small)
            } else {
                Button("Open Mail") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mail.app")) }.controlSize(.small)
            }
        }
    }
}

// MARK: - 8. Updates

struct UpdatesCard: View {
    @Bindable var model: SpeedModel

    var body: some View {
        SpeedCard(title: String(localized: "Updates you've been putting off"), icon: "arrow.down.circle.fill", color: Tidy.orange,
                  subtitle: String(localized: "Performance and battery fixes ship in updates all the time. An update that has been waiting for weeks is a speed-up you already own.")) {
            HStack(spacing: 10) {
                if model.checkingUpdates {
                    ProgressView().controlSize(.small)
                    Text("Asking Apple…").foregroundStyle(.secondary)
                } else if let u = model.updates {
                    if u.isEmpty {
                        Label("macOS is up to date", systemImage: "checkmark.circle.fill").foregroundStyle(Tidy.green)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(u, id: \.self) { Text("• \($0)") }
                        }
                    }
                } else {
                    Button("Check for macOS updates") { model.checkUpdates() }
                }
                Spacer()
            }
            HStack {
                Button("Open Software Update") { SystemInfo.openSettings("com.apple.Software-Update-Settings.extension") }
                Button("App Store updates") { NSWorkspace.shared.open(URL(string: "macappstore://showUpdatesPage")!) }
                Spacer()
            }
        }
    }
}

// MARK: - 9. Lighter look

struct LighterLookCard: View {
    @Bindable var model: SpeedModel

    var body: some View {
        SpeedCard(title: String(localized: "A lighter look for older Macs"), icon: "sparkle", color: Tidy.pink,
                  subtitle: String(localized: "Animations, see-through menus, and moving wallpapers all cost graphics power. Turning them down makes an older Mac feel noticeably snappier and costs nothing.")) {
            status("Reduce motion", model.reduceMotion)
            status("Reduce transparency", model.reduceTransparency)
            HStack {
                Button("Open Accessibility Display settings") { SystemInfo.openSettings("com.apple.Accessibility-Display-Settings.extension") }
                Button("Wallpaper settings") { SystemInfo.openSettings("com.apple.Wallpaper-Settings.extension") }
                Spacer()
            }
            Text("Turn on both switches in Accessibility > Display, and pick a still picture as the wallpaper. Everything works the same, it just stops animating.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func status(_ label: LocalizedStringKey, _ on: Bool?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: on == true ? "checkmark.circle.fill" : "circle").foregroundStyle(on == true ? Tidy.green : .secondary)
            Text(label)
            Spacer()
            Text(on == true ? String(localized: "On") : String(localized: "Off")).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
