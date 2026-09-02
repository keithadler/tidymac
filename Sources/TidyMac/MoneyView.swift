//  The Money tab: seven cards about not spending money you don't need to, plus its model.

import SwiftUI
import Observation

@MainActor
@Observable
final class MoneyModel {
    var subscriptions: [SubscriptionApp]?
    var clouds: [CloudDrive]?
    var storage: StorageMath?
    var speedTest: SpeedTest?
    var testing = false
    var hardware: HardwareInfo?
    var battery: BatteryInfo?
    var alternatives: [BuiltInAlternative]?
    var memory: MemoryInfo?
    var health: HealthReport?
    var loading = false
    var demo = false
    var message: String?

    var planMbps: Int {
        get { UserDefaults.standard.integer(forKey: "planMbps") }
        set { UserDefaults.standard.set(newValue, forKey: "planMbps") }
    }

    func load() {
        guard !loading, !demo else { return }
        loading = true
        Task {
            async let subs = Task.detached { MoneyInfo.subscriptions() }.value
            async let cl = Task.detached { MoneyInfo.cloudDrives() }.value
            async let hw = Task.detached { MoneyInfo.hardware() }.value
            async let alt = Task.detached { MoneyInfo.builtInAlternatives() }.value
            async let h = Task.detached { SystemInfo.health() }.value
            memory = SystemInfo.memory()
            subscriptions = await subs
            clouds = await cl
            hardware = await hw
            alternatives = await alt
            health = await h
            battery = health?.battery
            storage = await Task.detached { MoneyInfo.storageMath() }.value
            loading = false
        }
    }

    func runSpeedTest() {
        guard !testing else { return }
        testing = true
        Task {
            speedTest = await Task.detached { MoneyInfo.speedTest() }.value
            if speedTest == nil { message = String(localized: "Couldn't reach the speed-test server. Check the connection and try again.") }
            testing = false
        }
    }

    var verdict: MacVerdict? {
        guard let hw = hardware else { return nil }
        return MoneyInfo.macVerdict(hw: hw, health: health, memory: memory, space: storage?.space ?? DiskSpace.current())
    }
}

struct MoneyView: View {
    @Bindable var model: MoneyModel
    @AppStorage(ViewOptions.compact) private var compact = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: compact ? 8 : 14) {
                    MacVerdictCard(model: model)
                    SubscriptionsCard(model: model)
                    InternetPlanCard(model: model)
                    StorageMathCard(model: model)
                    CloudDrivesCard(model: model)
                    BatteryDecisionCard(model: model)
                    AlternativesCard(model: model)
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle").foregroundStyle(.secondary)
                        Text("Prices are typical US figures for 2026 and change often. Tidy for Mac can't see what you actually pay, so every saving here is an \"if you're paying for this\".")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 4)
                }
                .padding(compact ? 12 : 20)
            }
            if let m = model.message {
                Divider()
                HStack { Image(systemName: "info.circle").foregroundStyle(Tidy.blue); Text(m).font(.callout); Spacer(); Button("OK") { model.message = nil }.controlSize(.small) }
                    .padding(.horizontal, 20).padding(.vertical, 10).background(.bar)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { model.load() } label: { Label("Check again", systemImage: "arrow.clockwise") }.disabled(model.loading)
            }
        }
        .onAppear { if model.subscriptions == nil { model.load() } }
    }
}

// MARK: - 6. Is this Mac done?

struct MacVerdictCard: View {
    @Bindable var model: MoneyModel

    var body: some View {
        let v = model.verdict
        let color = v.map { verdictColor($0.level) } ?? .gray
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(color.opacity(0.18)).frame(width: 56, height: 56)
                    Image(systemName: "laptopcomputer").font(.title2).foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(v?.headline ?? String(localized: "Checking this Mac…")).font(.title2.weight(.bold))
                    if let hw = model.hardware {
                        Text("\(hw.model) · \(hw.chip) · \(hw.memoryGB) GB memory").foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            if let v {
                ForEach(v.reasons, id: \.self) { r in
                    HStack(alignment: .top, spacing: 8) { Circle().fill(color).frame(width: 7, height: 7).padding(.top, 6); Text(r).font(.callout) }
                }
                Text(v.cheapestFix).font(.callout.weight(.semibold))
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(color.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(color.opacity(0.35)))
    }
}

// MARK: - 1. Subscriptions

struct SubscriptionsCard: View {
    @Bindable var model: MoneyModel

    var body: some View {
        SpeedCard(title: String(localized: "Subscriptions you may not be using"), icon: "creditcard.fill", color: Tidy.green,
                  subtitle: String(localized: "Apps that are normally paid monthly or yearly, and when each was last opened. Tidy can't see your bills, so treat these as questions, not accusations.")) {
            if let subs = model.subscriptions {
                if subs.isEmpty { Label("No subscription apps found.", systemImage: "checkmark.circle.fill").foregroundStyle(Tidy.green) }
                ForEach(subs) { s in
                    let idle = s.daysIdle ?? 9999
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: s.path)).resizable().frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(s.vendor).fontWeight(.medium)
                                if idle >= 60 {
                                    Text(s.lastUsed == nil ? "never opened" : "not opened in \(idle) days")
                                        .font(.caption.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Tidy.orange.opacity(0.15), in: Capsule()).foregroundStyle(Tidy.orange)
                                } else {
                                    Text("used \(idle == 0 ? "today" : "\(idle) days ago")").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Text(s.note).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Manage plan") { NSWorkspace.shared.open(URL(string: s.manageURL)!) }.controlSize(.small)
                    }
                    .padding(.vertical, 3)
                }
                HStack {
                    Button("App Store subscriptions") { NSWorkspace.shared.open(URL(string: "https://apps.apple.com/account/subscriptions")!) }
                    Spacer()
                }
            } else {
                HStack { ProgressView().controlSize(.small); Text("Checking…").foregroundStyle(.secondary) }
            }
        }
    }
}

// MARK: - 4. Internet plan

struct InternetPlanCard: View {
    @Bindable var model: MoneyModel
    @State private var plan: String = ""

    var body: some View {
        SpeedCard(title: String(localized: "Are you getting the internet you pay for?"), icon: "gauge.with.needle", color: Tidy.blue,
                  subtitle: String(localized: "A quick download test against a nearby server. Compare it with the speed on your bill. For a fair test, plug in with a cable or sit next to the router.")) {
            HStack(spacing: 10) {
                Text("Speed on your bill:")
                TextField("e.g. 300", text: $plan).frame(width: 80).textFieldStyle(.roundedBorder)
                    .onSubmit { model.planMbps = Int(plan) ?? 0 }
                    .onAppear { plan = model.planMbps > 0 ? "\(model.planMbps)" : "" }
                Text("Mbps").foregroundStyle(.secondary)
                Spacer()
                Button(model.testing ? "Testing…" : (model.speedTest == nil ? "Run the test" : "Test again")) { model.planMbps = Int(plan) ?? 0; model.runSpeedTest() }
                    .disabled(model.testing)
                if model.testing { ProgressView().controlSize(.small) }
            }
            if let t = model.speedTest {
                Text("\(Int(t.mbps)) Mbps download\(t.latencyMs.map { String(format: " · %.0f ms to respond", $0) } ?? "") · \(Bytes.string(Int64(t.bytes))) in \(String(format: "%.1f", t.seconds)) s")
                    .font(.title3.weight(.semibold).monospacedDigit())
                let plan = model.planMbps
                if plan > 0 {
                    let ratio = t.mbps / Double(plan)
                    if ratio < 0.5 {
                        tip(Tidy.orange, "That's under half of what you're paying for. Test again with a cable; if it's still low, call your provider: they'll often fix it or drop you to the cheaper plan you're actually getting.")
                    } else if ratio < 0.8 {
                        tip(.secondary, "A bit under the plan speed, which is normal on Wi-Fi. Fine.")
                    } else {
                        tip(Tidy.green, "You're getting what you pay for.")
                    }
                    if t.mbps > 150 && plan > 300 {
                        tip(.secondary, "Most households never use more than 100 Mbps at once. If the cheaper tier is a lot less per month, it will feel the same.")
                    }
                } else {
                    tip(.secondary, "Type the speed from your bill above to compare.")
                }
            }
        }
    }
}

// MARK: - 3. Storage math

struct StorageMathCard: View {
    @Bindable var model: MoneyModel

    var body: some View {
        SpeedCard(title: String(localized: "Before you buy more storage"), icon: "externaldrive.badge.plus", color: Tidy.purple,
                  subtitle: String(localized: "Storage upgrades are the most common thing people pay for that a tidy would have covered.")) {
            if let s = model.storage {
                if let sp = s.space {
                    Text("\(Bytes.string(sp.free)) free now. Tidy can free about \(Bytes.string(s.safeBytes)) safely, and another \(Bytes.string(s.reviewBytes)) if you go through the \"take a look first\" cards.")
                        .font(.callout)
                    let after = sp.free + s.safeBytes + s.reviewBytes
                    tip(after > sp.total / 5 ? Tidy.green : Tidy.orange,
                        after > sp.total / 5
                        ? "After a full tidy you'd have \(Bytes.string(after)) free, a fifth of the disk. No need to buy anything."
                        : "Even after a full tidy this disk is tight. An external SSD, about $\(Int(MoneyInfo.externalSSDPerTB)) per TB, is the cheapest fix; a bigger Mac is the most expensive.")
                }
                if let ic = s.icloudLocalBytes, ic > 1_000_000_000 {
                    Text("iCloud Drive keeps \(Bytes.string(ic)) on this Mac. Optimise Mac Storage lets macOS keep only recent files here and fetch the rest when opened.").font(.callout).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("For scale, iCloud storage plans (US, 2026):").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 14) {
                        ForEach(MoneyInfo.icloudTiers.prefix(3), id: \.gb) { t in
                            Text("\(t.gb >= 1000 ? "\(t.gb / 1000) TB" : "\(t.gb) GB") · $\(String(format: "%.2f", t.usdPerMonth))/mo").font(.caption.monospacedDigit())
                        }
                    }
                    Text("A year of the 2 TB plan costs about the same as a 2 TB external SSD you keep forever.").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Open Storage settings") { SystemInfo.openSettings("com.apple.settings.Storage") }
                    Spacer()
                }
            } else {
                HStack { ProgressView().controlSize(.small); Text("Adding up what a tidy would free…").foregroundStyle(.secondary) }
            }
        }
    }
}

// MARK: - 2. Cloud drives

struct CloudDrivesCard: View {
    @Bindable var model: MoneyModel

    var body: some View {
        if let clouds = model.clouds {
            let active = clouds.filter(\.installed)
            SpeedCard(title: String(localized: "Cloud drives"), icon: "icloud.fill", color: Tidy.teal,
                      subtitle: active.count >= 2
                        ? String(localized: "\(active.count) cloud drives on this Mac. Most households only need one, and each one above the free tier is a monthly bill.")
                        : String(localized: "One cloud drive. That's the right number.")) {
                ForEach(clouds) { c in
                    HStack(spacing: 10) {
                        Image(systemName: c.running ? "checkmark.icloud.fill" : "icloud").foregroundStyle(c.running ? Tidy.teal : .secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.name).fontWeight(.medium)
                            Text("\(c.running ? "running" : (c.installed ? "installed, not running" : "not installed"))\(c.localBytes.map { " · \(Bytes.string($0)) kept on this Mac" } ?? "")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Manage plan") {
                            if c.manageURL.hasPrefix("x-apple") { SystemInfo.openSettings(c.manageURL.replacingOccurrences(of: "x-apple.systempreferences:", with: "")) }
                            else { NSWorkspace.shared.open(URL(string: c.manageURL)!) }
                        }.controlSize(.small)
                    }
                    .padding(.vertical, 2)
                }
                if active.count >= 2 {
                    tip(Tidy.orange, "Pick the one that comes with something you already pay for (iCloud with an iPhone, Google One with Gmail, OneDrive with Microsoft 365), move the files over, and cancel the rest.")
                }
            }
        }
    }
}

// MARK: - 5. Battery decision

struct BatteryDecisionCard: View {
    @Bindable var model: MoneyModel

    var body: some View {
        if let d = MoneyInfo.batteryDecision(model.battery) {
            SpeedCard(title: String(localized: "Does the battery need replacing?"), icon: "battery.50percent", color: verdictColor(d.level),
                      subtitle: String(localized: "A straight answer, using Apple's own numbers, before anyone sells you a battery.")) {
                tip(verdictColor(d.level), LocalizedStringKey(d.text))
                HStack {
                    Button("Apple's battery service page") { NSWorkspace.shared.open(URL(string: "https://support.apple.com/mac/repair/service")!) }
                    Spacer()
                }
            }
        }
    }
}

// MARK: - 7. Built-in alternatives

struct AlternativesCard: View {
    @Bindable var model: MoneyModel

    var body: some View {
        if let alts = model.alternatives, !alts.isEmpty {
            SpeedCard(title: String(localized: "Things your Mac already does for free"), icon: "gift.fill", color: Tidy.pink,
                      subtitle: String(localized: "Paid apps on this Mac that overlap with something built in. Keep the paid one if you love it; this is only so you know.")) {
                ForEach(alts) { a in
                    HStack(alignment: .top, spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: a.path)).resizable().frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(a.installedApp)  →  \(a.builtIn)").fontWeight(.medium)
                            Text(a.note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if let o = a.open { Button("Open \(URL(fileURLWithPath: o).deletingPathExtension().lastPathComponent)") { NSWorkspace.shared.open(URL(fileURLWithPath: o)) }.controlSize(.small) }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }
}
