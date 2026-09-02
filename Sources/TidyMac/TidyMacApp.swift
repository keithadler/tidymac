//  Tidy for Mac — a friendly, safe cleanup and speed-up app for the whole family.
//  MIT licensed. See LICENSE.
//
//  App entry point. Declares every window (main Tidy/Speed window, receipts, uninstaller,
//  space map, menu bar tidy, disk map), the Settings scene, and the menu bar extra.
//  The init hook hands `tidy <command>` invocations to CLI.swift, which exits before any UI exists.

import SwiftUI

@main
struct TidyMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var cleanup = CleanupModel()
    @State private var speed = SpeedModel()
    @State private var money = MoneyModel()
    @State private var diskMap = ScanModel()
    @AppStorage("menuBar") private var menuBar = true
    @Environment(\.openWindow) private var openWindow

    init() {
        CLI.runIfRequested()   // `tidy <command>` runs here and exits; otherwise the GUI starts
    }

    var body: some Scene {
        WindowGroup("Tidy for Mac", id: "main") {
            MainView(cleanup: cleanup, speed: speed, money: money)
                .onAppear { Scheduler.shared.start(model: cleanup) }
        }
        .defaultSize(width: 900, height: 920)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("View") {
                Toggle("Compact Rows", isOn: Binding(
                    get: { UserDefaults.standard.bool(forKey: ViewOptions.compact) },
                    set: { UserDefaults.standard.set($0, forKey: ViewOptions.compact) }))
                    .keyboardShortcut("1", modifiers: [.command, .option])
                Toggle("Show Explanations", isOn: Binding(
                    get: { UserDefaults.standard.object(forKey: ViewOptions.blurbs) as? Bool ?? true },
                    set: { UserDefaults.standard.set($0, forKey: ViewOptions.blurbs) }))
                    .keyboardShortcut("2", modifiers: [.command, .option])
                Divider()
                Button("Expand All Cards") { cleanup.setAllExpanded(true) }.keyboardShortcut("e", modifiers: [.command, .option])
                Button("Collapse All Cards") { cleanup.setAllExpanded(false) }.keyboardShortcut("c", modifiers: [.command, .option])
                Divider()
                Button("Tidy") { UserDefaults.standard.set(0, forKey: "mainTab") }.keyboardShortcut("1", modifiers: .command)
                Button("Speed") { UserDefaults.standard.set(1, forKey: "mainTab") }.keyboardShortcut("2", modifiers: .command)
                Button("Money") { UserDefaults.standard.set(2, forKey: "mainTab") }.keyboardShortcut("3", modifiers: .command)
            }
            CommandGroup(after: .windowList) {
                Button("What Tidy for Mac did") { openWindow(id: "history") }.keyboardShortcut("h", modifiers: [.command, .shift])
                Button("Uninstall an App") { openWindow(id: "uninstall") }.keyboardShortcut("u", modifiers: [.command, .shift])
                Button("Space Map") { openWindow(id: "spacemap") }.keyboardShortcut("m", modifiers: [.command, .shift])
                Button("Tidy the Menu Bar") { openWindow(id: "menubar") }.keyboardShortcut("b", modifiers: [.command, .shift])
                Button("Sort Desktop & Downloads") { openWindow(id: "sorter") }.keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Disk Map (Advanced)") { openWindow(id: "diskmap") }.keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }

        Window("What Tidy for Mac did", id: "history") { HistoryView() }
            .defaultSize(width: 760, height: 560)

        Window("Uninstall an App", id: "uninstall") { UninstallView(model: UninstallModel.shared) }
            .defaultSize(width: 900, height: 620)

        Window("Sort Desktop & Downloads", id: "sorter") { SorterView() }
            .defaultSize(width: 760, height: 600)

        Window("Menu Bar", id: "menubar") { MenuBarTidyView() }
            .defaultSize(width: 680, height: 760)

        Window("Space Map", id: "spacemap") { SpaceMapView() }
            .defaultSize(width: 1000, height: 700)

        Window("Disk Map", id: "diskmap") { ContentView(model: diskMap) }
            .defaultSize(width: 1280, height: 820)

        Settings { SettingsView() }

        MenuBarExtra("Tidy for Mac", systemImage: "sparkles", isInserted: $menuBar) {
            MenuBarContent(model: cleanup)
        }
    }
}
