//  Colours and glyphs for the Disk Map, one per data type (physical disk, partition, container,
//  each APFS volume role, snapshot), plus the legend order.

import SwiftUI

/// One color per data type. Chosen to read on both light and dark backgrounds.
enum Theme {
    static let physicalDisk = Color(red: 0.42, green: 0.45, blue: 0.50)
    static let partition    = Color(red: 0.55, green: 0.60, blue: 0.68)
    static let container    = Color(red: 0.38, green: 0.36, blue: 0.82)
    static let snapshot     = Color(red: 0.12, green: 0.68, blue: 0.86)

    static func color(for role: VolumeRole) -> Color {
        switch role {
        case .system:   return Color(red: 0.16, green: 0.47, blue: 0.96)
        case .data:     return Color(red: 0.18, green: 0.70, blue: 0.40)
        case .preboot:  return Color(red: 0.96, green: 0.58, blue: 0.14)
        case .recovery: return Color(red: 0.90, green: 0.27, blue: 0.27)
        case .update:   return Color(red: 0.84, green: 0.70, blue: 0.12)
        case .vm:       return Color(red: 0.60, green: 0.38, blue: 0.85)
        case .xart, .hardware: return Color(red: 0.18, green: 0.64, blue: 0.68)
        case .backup:   return Color(red: 0.58, green: 0.42, blue: 0.24)
        case .user:     return Color(red: 0.36, green: 0.60, blue: 0.30)
        case .none:     return Color(red: 0.60, green: 0.60, blue: 0.60)
        }
    }

    static func color(for node: DiskNode) -> Color {
        switch node.kind {
        case .physicalDisk: return physicalDisk
        case .partition:    return partition
        case .container:    return container
        case .snapshot:     return snapshot
        case .volume:       return color(for: node.primaryRole ?? .none)
        }
    }

    static func glyph(for node: DiskNode) -> String {
        switch node.kind {
        case .physicalDisk: return "internaldrive"
        case .partition:    return "rectangle.split.3x1"
        case .container:    return "shippingbox"
        case .snapshot:     return "camera.aperture"
        case .volume:
            switch node.primaryRole ?? .none {
            case .system:   return "apple.logo"
            case .data:     return "folder"
            case .preboot:  return "power"
            case .recovery: return "cross.case"
            case .update:   return "arrow.down.circle"
            case .vm:       return "memorychip"
            case .xart, .hardware: return "cpu"
            case .backup:   return "clock.arrow.circlepath"
            case .user, .none: return "externaldrive"
            }
        }
    }

    /// Entries for the legend, in display order.
    static let legend: [(label: String, color: Color)] = [
        ("Physical disk", physicalDisk),
        ("Partition", partition),
        ("APFS container", container),
        ("System (sealed)", color(for: .system)),
        ("Data", color(for: .data)),
        ("Preboot", color(for: .preboot)),
        ("Recovery", color(for: .recovery)),
        ("Update", color(for: .update)),
        ("VM / swap", color(for: .vm)),
        ("xART / Hardware", color(for: .xart)),
        ("Snapshot", snapshot),
    ]
}
