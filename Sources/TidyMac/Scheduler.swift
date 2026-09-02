//  Background behaviour: weekly quiet tidy, "almost full" warnings, monthly nudges, and
//  launch-at-login via SMAppService. Notifier guards every notification call so text-mode runs
//  and bare binaries (which have no bundle) never touch UNUserNotificationCenter.

import Foundation
import AppKit
import UserNotifications
import ServiceManagement

/// Local notifications, guarded so text-mode runs and bare binaries never touch the notification center.
enum Notifier {
    static var available: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }

    static func requestPermission() async -> Bool {
        guard available else { return false }
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func post(title: String, body: String) {
        guard available else { return }
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}

/// Weekly quiet tidy, "almost full" warnings, and gentle nudges. Runs while the app is open,
/// which with Launch at Login and menu bar mode means always.
@MainActor
final class Scheduler {
    static let shared = Scheduler()
    private var timer: Timer?
    private let defaults = UserDefaults.standard

    enum Key {
        static let weeklyTidy = "weeklyTidy"
        static let reminders = "reminders"
        static let lastAutoTidy = "lastAutoTidy"
        static let lastFullWarning = "lastFullWarning"
        static let lastNudge = "lastNudge"
        static let firstLaunch = "firstLaunch"
    }

    func start(model: CleanupModel) {
        if defaults.object(forKey: Key.firstLaunch) == nil { defaults.set(Date(), forKey: Key.firstLaunch) }
        check(model)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { _ in
            Task { @MainActor in Scheduler.shared.check(model) }
        }
    }

    private func days(since key: String) -> Double {
        guard let d = defaults.object(forKey: key) as? Date else { return .infinity }
        return Date().timeIntervalSince(d) / 86400
    }

    /// Runs on launch and every six hours. Each nudge has its own timestamp so a notification
    /// fires at most once per period even if the app is relaunched repeatedly. The weekly tidy
    /// stamps *before* running so a crash mid-tidy can't cause a loop of retries.
    func check(_ model: CleanupModel) {
        if defaults.bool(forKey: Key.weeklyTidy), days(since: Key.lastAutoTidy) >= 7 {
            defaults.set(Date(), forKey: Key.lastAutoTidy)
            Task {
                if let s = await model.quietTidy() {
                    Notifier.post(title: String(localized: "Tidy for Mac tidied up"),
                                  body: String(localized: "\(Bytes.string(s.totalSize)) of caches and old files moved to the Trash. Open Tidy for Mac to see the receipt."))
                }
            }
        }
        guard defaults.bool(forKey: Key.reminders) else { return }
        if let s = DiskSpace.current(), s.usedFraction >= 0.9, days(since: Key.lastFullWarning) >= 1 {
            defaults.set(Date(), forKey: Key.lastFullWarning)
            Notifier.post(title: String(localized: "Your Mac is almost full"),
                          body: String(localized: "Only \(Bytes.string(s.free)) left. Open Tidy for Mac to make some space."))
        }
        let last = History.shared.lastTidy ?? (defaults.object(forKey: Key.firstLaunch) as? Date) ?? Date()
        if Date().timeIntervalSince(last) > 30 * 86400, days(since: Key.lastNudge) >= 7 {
            defaults.set(Date(), forKey: Key.lastNudge)
            Notifier.post(title: String(localized: "Time for a quick tidy?"),
                          body: String(localized: "It's been a month. A tidy takes about a minute."))
        }
    }

    // MARK: Launch at login

    static var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    static func setLaunchAtLogin(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
