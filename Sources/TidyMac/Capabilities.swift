//  What this Mac and this macOS can do. Checked once at launch and used to hide or disable
//  anything Tidy for Mac can't back up with a real result: a missing command-line tool, a machine
//  without a battery or Wi-Fi, an older preference layout, or a permission the user declined.
//  The rule: never show a control that can't work, and never show a guess as a fact.

import Foundation
import AppKit

enum Capabilities {
    static let osVersion = ProcessInfo.processInfo.operatingSystemVersion
    static var osString: String { "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)" }
    static func atLeast(_ major: Int, _ minor: Int = 0) -> Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: 0))
    }

    static let isAppleSilicon: Bool = (SystemInfo.sysctlInt("hw.optional.arm64") ?? 0) == 1

    /// Stock tools the Speed tab shells out to. All ship with macOS, but a locked-down or
    /// unusual install can be missing one, and a future macOS can drop one.
    static func has(_ tool: String) -> Bool { FileManager.default.isExecutableFile(atPath: tool) }

    static let dig = has("/usr/bin/dig")
    static let ping = has("/sbin/ping")
    static let tmutil = has("/usr/bin/tmutil")
    static let fdesetup = has("/usr/bin/fdesetup")
    static let firewall = has("/usr/libexec/ApplicationFirewall/socketfilterfw")
    static let sysadminctl = has("/usr/sbin/sysadminctl")
    static let spctl = has("/usr/sbin/spctl")
    static let softwareupdate = has("/usr/sbin/softwareupdate")
    static let systemProfiler = has("/usr/sbin/system_profiler")
    static let mdls = has("/usr/bin/mdls")
    static let pmset = has("/usr/bin/pmset")
    static let lpstat = has("/usr/bin/lpstat")
    static let diskutil = has("/usr/sbin/diskutil")
    static let qlmanage = has("/usr/bin/qlmanage")
    static let dscacheutil = has("/usr/bin/dscacheutil")
    static let lsregister = has("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister")

    /// True when the Mac reports a battery at all (laptops). Desktops hide the battery cards.
    static var hasBattery: Bool {
        !SystemInfo.run("/usr/bin/pmset", ["-g", "batt"], timeout: 5).contains("No batteries")
    }

    /// True when a Wi-Fi interface exists, whether or not it is connected.
    static var hasWiFi: Bool {
        SystemInfo.run("/usr/sbin/networksetup", ["-listallhardwareports"], timeout: 5).contains("Wi-Fi")
    }

    /// Whether Tidy for Mac may talk to an app through Apple Events. Nil until a call has been made;
    /// false after macOS refuses with -1743 (not permitted) so the UI can point at the fix.
    static func automationDenied(_ error: NSDictionary?) -> Bool {
        guard let err = error, let n = err[NSAppleScript.errorNumber] as? Int else { return false }
        return n == -1743 || n == -1744   // errAEEventNotPermitted / errAEEventWouldRequireUserConsent
    }

    static let automationPane = "com.apple.settings.PrivacySecurity.extension?Privacy_Automation"
    static let fullDiskPane = "com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles"
}
