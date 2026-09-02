//  "Tidy the menu bar" window. Apple's icons are toggled by writing the same Control Center
//  preferences System Settings writes (see MenuBarTidy.set for the three key forms macOS has
//  used) and restarting Control Center. Other apps' icons can't be hidden by anyone but that
//  app, so the window offers: open its settings, stop it at login, or quit it.

import SwiftUI
import Observation

// MARK: - Apple's menu bar icons (Control Center preferences)

struct MenuBarItemSetting: Identifiable, Sendable {
    let key: String
    let name: String
    let note: String
    var visible: Bool?
    var id: String { key }
}

enum MenuBarTidy {
    static let domain = "com.apple.controlcenter"

    /// Control Center modules that can show an icon in the menu bar, with the key macOS stores them under.
    static let items: [(key: String, name: String, note: String)] = [
        ("WiFi", "Wi-Fi", "Handy for switching networks. Also in Control Center."),
        ("Bluetooth", "Bluetooth", "Only useful if you swap headphones or mice often."),
        ("Sound", "Sound", "Volume is on the keyboard too."),
        ("Battery", "Battery", "Worth keeping on a laptop."),
        ("Display", "Display brightness", "Brightness is on the keyboard too."),
        ("FocusModes", "Focus", "Shows when a Focus is on."),
        ("ScreenMirroring", "Screen Mirroring", "Only shows while mirroring, usually."),
        ("NowPlaying", "Now Playing", "Music controls. Also in Control Center."),
        ("UserSwitcher", "Fast User Switching", "Only if several people share this Mac."),
        ("KeyboardBrightness", "Keyboard brightness", "Rarely needed in the bar."),
        ("Hearing", "Hearing", "Hearing-device controls."),
        ("AccessibilityShortcuts", "Accessibility Shortcuts", ""),
        ("MusicRecognition", "Music Recognition", "Shazam button."),
        ("Siri", "Siri", ""),
    ]

    /// macOS has stored the "Show in Menu Bar" choice three ways over the years, and a Mac upgraded
    /// through several versions can have any of them:
    ///   - "NSStatusItem VisibleCC <key>"  Bool   (macOS 14 and later; what System Settings writes today)
    ///   - "NSStatusItem Visible <key>"    Bool   (macOS 11–13)
    ///   - "<key>"                         Int    (oldest: 18 = always show, 2 = show when active, 24 = don't show)
    /// Reads prefer the newest form; writes set all three so the change sticks whichever one
    /// this build of Control Center reads.
    static func isVisible(_ key: String) -> Bool? {
        // macOS 14+ writes "NSStatusItem VisibleCC <key>"; older builds "NSStatusItem Visible <key>"; the module int is the oldest form.
        if let b = CFPreferencesCopyAppValue("NSStatusItem VisibleCC \(key)" as CFString, domain as CFString) as? Bool { return b }
        if let b = CFPreferencesCopyAppValue("NSStatusItem Visible \(key)" as CFString, domain as CFString) as? Bool { return b }
        if let n = CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? Int { return n != 24 }
        return nil
    }

    static func read() -> [MenuBarItemSetting] {
        items.map { MenuBarItemSetting(key: $0.key, name: $0.name, note: $0.note, visible: isVisible($0.key)) }
    }

    /// True when Control Center's preference domain holds any menu bar visibility keys at all.
    /// If not, this macOS stores them somewhere new and the toggles would silently do nothing,
    /// so the window shows the System Settings link instead.
    static var supported: Bool {
        guard let keys = CFPreferencesCopyKeyList(domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String] else { return false }
        return keys.contains { $0.hasPrefix("NSStatusItem Visible") }
    }

    /// Spotlight moved into Control Center's list on recent macOS; older versions use Spotlight's own key.
    static var spotlightInControlCenter: Bool {
        CFPreferencesCopyAppValue("NSStatusItem VisibleCC Spotlight" as CFString, domain as CFString) != nil
            || CFPreferencesCopyAppValue("Spotlight" as CFString, domain as CFString) != nil
    }

    static var spotlightVisible: Bool {
        if spotlightInControlCenter { return isVisible("Spotlight") ?? true }
        return !((CFPreferencesCopyAppValue("MenuItemHidden" as CFString, "com.apple.Spotlight" as CFString) as? Bool) ?? false)
    }

    /// Writes the preference the way System Settings does, then lets Control Center pick it up.
    static func set(_ key: String, visible: Bool) -> String? {
        let a = SystemInfo.run("/usr/bin/defaults", ["write", domain, "NSStatusItem VisibleCC \(key)", "-bool", visible ? "true" : "false"], timeout: 5)
        let b = SystemInfo.run("/usr/bin/defaults", ["write", domain, "NSStatusItem Visible \(key)", "-bool", visible ? "true" : "false"], timeout: 5)
        let c = SystemInfo.run("/usr/bin/defaults", ["write", domain, key, "-int", visible ? "18" : "24"], timeout: 5)
        _ = SystemInfo.run("/usr/bin/killall", ["ControlCenter"], timeout: 5)
        let err = (a + b + c).trimmingCharacters(in: .whitespacesAndNewlines)
        return err.isEmpty ? nil : err
    }

    static func setSpotlight(visible: Bool) -> String? {
        if spotlightInControlCenter { return set("Spotlight", visible: visible) }
        let a = SystemInfo.run("/usr/bin/defaults", ["write", "com.apple.Spotlight", "MenuItemHidden", "-bool", visible ? "false" : "true"], timeout: 5)
        _ = SystemInfo.run("/usr/bin/killall", ["Spotlight"], timeout: 5)
        let err = a.trimmingCharacters(in: .whitespacesAndNewlines)
        return err.isEmpty ? nil : err
    }
}

// MARK: - Model

@MainActor
@Observable
final class MenuBarModel {
    var apple: [MenuBarItemSetting] = []
    var demo = false
    var supported = MenuBarTidy.supported
    var spotlight = true
    var apps: [AppLoad] = []
    var loginItems: [LoginItem] = []
    var message: String?
    private var timer: Timer?

    func start() {
        guard !demo else { return }
        reload()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in Task { @MainActor in self.refreshApps() } }
    }

    func stop() { timer?.invalidate(); timer = nil }

    func reload() {
        supported = MenuBarTidy.supported
        apple = MenuBarTidy.read()
        spotlight = MenuBarTidy.spotlightVisible
        refreshApps()
        Task { loginItems = SystemInfo.loginItems().items }
    }

    func refreshApps() {
        Task {
            let procs = await Task.detached { SystemInfo.processes() }.value
            apps = SystemInfo2.menuBarApps(procs)
        }
    }

    func toggle(_ item: MenuBarItemSetting) {
        let on = !(item.visible ?? true)
        if let e = MenuBarTidy.set(item.key, visible: on) { message = e; return }
        if let i = apple.firstIndex(where: { $0.id == item.id }) { apple[i].visible = on }
        message = on ? String(localized: "\(item.name) is back in the menu bar.") : String(localized: "\(item.name) hidden. It's still in Control Center, and you can bring it back here any time.")
    }

    func toggleSpotlight() {
        let on = !spotlight
        if let e = MenuBarTidy.setSpotlight(visible: on) { message = e; return }
        spotlight = on
        message = on ? String(localized: "Spotlight icon shown.") : String(localized: "Spotlight icon hidden. ⌘ Space still opens Spotlight.")
    }

    func open(_ app: AppLoad) {
        guard let p = app.bundlePath else { return }
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: p), configuration: NSWorkspace.OpenConfiguration())
        message = String(localized: "Look for “Show in menu bar” or “Hide icon” in \(app.name)'s settings.")
    }

    func quit(_ app: AppLoad) {
        guard let p = app.bundlePath else { return }
        for r in NSWorkspace.shared.runningApplications where r.bundleURL?.path == p { r.terminate() }
        message = String(localized: "\(app.name) closed. Its icon will come back next time it opens.")
        Task { try? await Task.sleep(for: .seconds(1.5)); refreshApps() }
    }

    func loginItem(for app: AppLoad) -> LoginItem? {
        loginItems.first { $0.path == app.bundlePath || $0.name.lowercased() == app.name.lowercased() }
    }

    func removeLoginItem(_ li: LoginItem) {
        if let e = SystemInfo.removeLoginItem(li.name) { message = e; return }
        loginItems.removeAll { $0.id == li.id }
        message = String(localized: "\(li.name) won't open at login any more, so its icon won't appear until you open it.")
    }
}

// MARK: - View

struct MenuBarTidyView: View {
    @State private var model: MenuBarModel

    @MainActor init(model: MenuBarModel? = nil) { _model = State(initialValue: model ?? MenuBarModel()) }
    @AppStorage("menuBar") private var tidyMacIcon = true

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tidy the menu bar").font(.title.weight(.bold))
                        Text("Fewer icons, less clutter, a little less memory. Nothing here is permanent.").foregroundStyle(.secondary)
                    }

                    // Reorder
                    GroupBox {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "command").font(.title).foregroundStyle(Tidy.blue).frame(width: 36)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("To move an icon: hold ⌘ and drag it").font(.headline)
                                Text("Works for every icon, Apple's and other apps'. Drag an Apple icon right off the bar to remove it. Tidy for Mac can't reach across and drag for you, but that's all there is to it.")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                        }
                        .padding(4)
                    }

                    // Apple's icons
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Apple's icons").font(.headline)
                            Text("Everything here stays available in Control Center, the switches icon at the top right. Hiding just removes the duplicate.")
                                .font(.caption).foregroundStyle(.secondary)
                            if !model.supported {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "info.circle").foregroundStyle(Tidy.blue)
                                    Text("This version of macOS (\(Capabilities.osString)) keeps these switches somewhere Tidy for Mac can't reach yet. Use the Control Center settings button below; it's the same list.")
                                        .font(.callout)
                                }
                                .padding(8).background(Tidy.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            }
                            ForEach(model.apple) { item in
                                HStack(spacing: 10) {
                                    Toggle("", isOn: Binding(get: { item.visible ?? true }, set: { _ in model.toggle(item) }))
                                        .toggleStyle(.switch).labelsHidden().controlSize(.small)
                                        .disabled(!model.supported)
                                        .accessibilityLabel(Text("Show \(item.name) in the menu bar"))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.name)
                                        if !item.note.isEmpty { Text(item.note).font(.caption).foregroundStyle(.secondary) }
                                    }
                                    Spacer()
                                    if item.visible == nil { Text("default").font(.caption).foregroundStyle(.tertiary) }
                                }
                            }
                            Divider()
                            HStack(spacing: 10) {
                                Toggle("", isOn: Binding(get: { model.spotlight }, set: { _ in model.toggleSpotlight() }))
                                    .toggleStyle(.switch).labelsHidden().controlSize(.small)
                                    .disabled(!model.supported)
                                    .accessibilityLabel(Text("Show Spotlight in the menu bar"))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Spotlight")
                                    Text("⌘ Space opens it anyway.").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            HStack(spacing: 10) {
                                Toggle("", isOn: $tidyMacIcon).toggleStyle(.switch).labelsHidden().controlSize(.small)
                                    .accessibilityLabel(Text("Show Tidy for Mac in the menu bar"))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Tidy for Mac")
                                    Text("The sparkle. Reminders and the weekly tidy need it, but it's your call.").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            Button("Open Control Center settings") { SystemInfo.openSettings("com.apple.ControlCenter-Settings.extension") }.padding(.top, 4)
                        }
                        .padding(4)
                    }

                    // Other apps
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Other apps' icons").font(.headline)
                            Text("Each app decides whether it shows an icon. Open the app and look for “Show in menu bar” in its settings. Or stop the app opening at login and the icon goes with it.")
                                .font(.caption).foregroundStyle(.secondary)
                            if model.apps.isEmpty {
                                Text("No other apps are in the menu bar right now.").foregroundStyle(.secondary)
                            }
                            ForEach(model.apps) { app in
                                HStack(spacing: 10) {
                                    if let p = app.bundlePath { Image(nsImage: NSWorkspace.shared.icon(forFile: p)).resizable().frame(width: 24, height: 24) }
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(app.name)
                                        Text("\(Bytes.string(app.memory)) of memory").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Its settings") { model.open(app) }.controlSize(.small)
                                    if let li = model.loginItem(for: app) {
                                        Button("Don't open at login") { model.removeLoginItem(li) }.controlSize(.small)
                                    }
                                    Button("Quit") { model.quit(app) }.controlSize(.small)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .padding(4)
                    }

                    // Hiding everything else
                    GroupBox {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "eye.slash").font(.title2).foregroundStyle(Tidy.purple).frame(width: 36)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Want icons tucked away but still reachable?").font(.headline)
                                Text("macOS has no built-in way to collapse other apps' icons. Ice is a free, open-source app that adds a hidden section to the menu bar. Tidy for Mac doesn't bundle it, so this is just a pointer.")
                                    .font(.callout).foregroundStyle(.secondary)
                                Button("Learn about Ice") { NSWorkspace.shared.open(URL(string: "https://icemenubar.app")!) }.controlSize(.small)
                            }
                        }
                        .padding(4)
                    }
                }
                .padding(20)
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
        .frame(minWidth: 620, minHeight: 600)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }
}
