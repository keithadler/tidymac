//  Settings window: General (menu bar, launch at login, weekly tidy, reminders), Protected
//  (the user's never-touch folders plus the built-in list), About.

import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            ProtectedSettings().tabItem { Label("Protected", systemImage: "shield.fill") }
            AboutSettings().tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 460)
    }
}

struct GeneralSettings: View {
    @AppStorage("autoUpdateCheck") private var autoUpdate = false
    @AppStorage("menuBar") private var menuBar = true
    @AppStorage(Scheduler.Key.weeklyTidy) private var weeklyTidy = false
    @AppStorage(Scheduler.Key.reminders) private var reminders = true
    @State private var launchAtLogin = Scheduler.launchAtLogin
    @State private var loginError: String?
    @State private var notifDenied = false

    var body: some View {
        Form {
            Section {
                Toggle("Show Tidy for Mac in the menu bar", isOn: $menuBar)
                Toggle("Open Tidy for Mac when I log in", isOn: $launchAtLogin)
                Toggle("Check for a new version once a day", isOn: $autoUpdate)
                Text("One request to GitHub, no identifiers. A new version is offered as a download; nothing installs by itself.").font(.caption).foregroundStyle(.secondary)
                    .onChange(of: launchAtLogin) { _, on in
                        loginError = Scheduler.setLaunchAtLogin(on)
                        if loginError != nil { launchAtLogin = Scheduler.launchAtLogin }
                    }
                if let e = loginError { Text(e).font(.caption).foregroundStyle(Tidy.red) }
                Text("Together these keep the sparkle in the menu bar so reminders and the weekly tidy can run.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Tidy the safe things every week", isOn: $weeklyTidy)
                    .onChange(of: weeklyTidy) { _, on in if on { askForNotifications() } }
                Text("Only app caches, logs, old installers, and developer caches. Never anything from a \"take a look first\" card. A receipt is saved every time.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Remind me when it's time to tidy, or when the disk is almost full", isOn: $reminders)
                    .onChange(of: reminders) { _, on in if on { askForNotifications() } }
                if notifDenied {
                    Text("Notifications are turned off for Tidy for Mac in System Settings > Notifications, so reminders will be quiet.")
                        .font(.caption).foregroundStyle(Tidy.orange)
                }
            }
            Section {
                Text("Language follows System Settings > General > Language & Region. Tidy for Mac speaks English and Spanish.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func askForNotifications() {
        Task { notifDenied = !(await Notifier.requestPermission()) }
    }
}

struct ProtectedSettings: View {
    @State private var paths = Protection.userPaths
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Folders Tidy for Mac must never touch").font(.headline)
            Text("Anything inside these shows a shield and can't be checked. Photos, Music, Mail, iCloud Drive, passwords, and Time Machine are always protected.")
                .font(.caption).foregroundStyle(.secondary)
            List(selection: $selection) {
                ForEach(paths, id: \.self) { p in
                    HStack {
                        Image(systemName: "folder.fill").foregroundStyle(Tidy.blue).accessibilityHidden(true)
                        Text(p.replacingOccurrences(of: NSHomeDirectory(), with: "~")).lineLimit(1).truncationMode(.middle)
                    }
                    .tag(p)
                }
            }
            .listStyle(.bordered)
            HStack {
                Button("Add Folder…") { addFolder() }
                Button("Remove") {
                    if let s = selection { Protection.remove(s); paths = Protection.userPaths; selection = nil }
                }
                .disabled(selection == nil)
                Spacer()
            }
            DisclosureGroup("Always protected") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Protection.builtIn, id: \.match) { r in
                            Text("• \(r.label)").font(.caption)
                        }
                    }
                }
                .frame(maxHeight: 90)
            }
            .font(.caption)
        }
        .padding()
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Protect")
        if panel.runModal() == .OK {
            for u in panel.urls { Protection.add(u.path) }
            paths = Protection.userPaths
        }
    }
}

struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 80, height: 80)
            Text("Tidy for Mac").font(.title.weight(.bold))
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")").foregroundStyle(.secondary)
            Text("A friendly, safe cleanup for the whole family. Everything goes to the Trash first. Nothing you made is ever a candidate.")
                .multilineTextAlignment(.center).frame(maxWidth: 380).foregroundStyle(.secondary)
            Text("Free and open source (MIT), built without Xcode.").font(.caption).foregroundStyle(.tertiary)
            Text("Mac and macOS are trademarks of Apple Inc. This app is independent and not authorized, sponsored, or approved by Apple Inc.")
                .font(.caption2).foregroundStyle(.tertiary).multilineTextAlignment(.center).frame(maxWidth: 380)
        }
        .padding()
    }
}
