//  The never-touch list: built-in rules for fragile things (photo libraries, mail, iCloud Drive,
//  passwords, backups, keys, game saves) plus paths the user adds in Settings. Scanner marks
//  matching items with a shield and the UI refuses to select them.

import Foundation

/// Things Tidy for Mac will never offer to move, plus the user's own never-touch folders.
enum Protection {
    struct Rule: Sendable {
        let match: String   // lowercase substring of the full path
        let label: String
    }

    static let builtIn: [Rule] = [
        Rule(match: ".photoslibrary", label: String(localized: "Photos library")),
        Rule(match: ".musiclibrary", label: String(localized: "Music library")),
        Rule(match: ".imovielibrary", label: String(localized: "iMovie library")),
        Rule(match: ".fcpbundle", label: String(localized: "Final Cut project")),
        Rule(match: ".logicx", label: String(localized: "Logic project")),
        Rule(match: ".band", label: String(localized: "GarageBand project")),
        Rule(match: "/library/mail", label: String(localized: "Mail")),
        Rule(match: "/library/messages", label: String(localized: "Messages")),
        Rule(match: "/library/mobile documents", label: String(localized: "iCloud Drive")),
        Rule(match: "/library/cloudstorage", label: String(localized: "cloud drive")),
        Rule(match: "/library/keychains", label: String(localized: "passwords")),
        Rule(match: "/library/application support/1password", label: String(localized: "1Password")),
        Rule(match: "/library/application support/addressbook", label: String(localized: "Contacts")),
        Rule(match: "/library/application support/minecraft/saves", label: String(localized: "Minecraft worlds")),
        Rule(match: "/library/application support/steam/steamapps", label: String(localized: "Steam games")),
        Rule(match: "backups.backupdb", label: String(localized: "Time Machine backup")),
        Rule(match: "/.ssh", label: String(localized: "SSH keys")),
        Rule(match: "/.gnupg", label: String(localized: "encryption keys")),
        Rule(match: "/library/application support/mobilesync/backup", label: String(localized: "device backup")),
    ]

    static let defaultsKey = "protectedPaths"

    static var userPaths: [String] {
        get { UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    /// Why a path is protected, or nil if it isn't. Device backups are exempt from the built-in
    /// rule when scanned by the backups card itself, which passes `allowBackups`.
    static func reason(for path: String, allowBackups: Bool = false) -> String? {
        let l = path.lowercased()
        for r in builtIn where l.contains(r.match) {
            if allowBackups && r.match.hasSuffix("mobilesync/backup") { continue }
            return r.label
        }
        for p in userPaths where path == p || path.hasPrefix(p.hasSuffix("/") ? p : p + "/") {
            return String(localized: "on your protected list")
        }
        return nil
    }

    static func add(_ path: String) {
        var p = userPaths
        if !p.contains(path) { p.append(path) }
        userPaths = p
    }

    static func remove(_ path: String) {
        userPaths = userPaths.filter { $0 != path }
    }
}
