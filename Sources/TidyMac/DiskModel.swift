//  Types for the Disk Map: DiskNode (one row in the tree), BootInfo (facts about what is
//  booted), DiskScan (the whole result), plus the byte formatter shared by the whole app.

import Foundation

enum NodeKind: String, Sendable {
    case physicalDisk = "Physical disk"
    case partition = "Partition"
    case container = "APFS container"
    case volume = "APFS volume"
    case snapshot = "APFS snapshot"
}

/// APFS volume roles as reported by `diskutil apfs list`.
enum VolumeRole: String, Sendable, CaseIterable {
    case system = "System"
    case data = "Data"
    case preboot = "Preboot"
    case recovery = "Recovery"
    case update = "Update"
    case vm = "VM"
    case xart = "xART"
    case hardware = "Hardware"
    case backup = "Backup"
    case user = "User"
    case none = "None"

    init(diskutil raw: String) {
        self = VolumeRole(rawValue: raw) ?? .none
    }

    var explanation: String {
        switch self {
        case .system:   return "Sealed, read-only macOS system volume. Booted via its snapshot."
        case .data:     return "Your files, apps and settings. Paired with the system volume in a volume group."
        case .preboot:  return "Boot loader and firmware-side data needed before the OS is up."
        case .recovery: return "macOS Recovery environment."
        case .update:   return "Staging area for OS updates."
        case .vm:       return "Swap and sleep image storage."
        case .xart:     return "Secure Enclave anti-replay storage."
        case .hardware: return "Firmware and hardware support data."
        case .backup:   return "Time Machine backup volume."
        case .user:     return "General-purpose user volume."
        case .none:     return "No APFS role assigned."
        }
    }
}

struct DiskNode: Identifiable, Sendable {
    var id: String
    var kind: NodeKind
    var name: String
    var deviceIdentifier: String
    var content: String
    var size: Int64
    var used: Int64?
    var free: Int64?
    var mountPoint: String?
    var roles: [VolumeRole]
    var isInternal: Bool
    var isBootDevice: Bool = false       // the thing mounted at /
    var onBootPath: Bool = false         // disk, partition, container, volume or snapshot leading to /
    var inBootVolumeGroup: Bool = false  // System + Data pair of the running OS
    var sealed: Bool = false
    var encrypted: Bool = false
    var fileVault: Bool = false
    var locked: Bool = false
    var physicalStores: [String] = []
    var uuid: String?
    var children: [DiskNode] = []

    var primaryRole: VolumeRole? { roles.first }

    /// Depth-first flattening with depth, used by the tree view.
    func flattened(depth: Int = 0) -> [(node: DiskNode, depth: Int)] {
        var out: [(DiskNode, Int)] = [(self, depth)]
        for c in children { out.append(contentsOf: c.flattened(depth: depth + 1)) }
        return out
    }

    func find(_ id: String) -> DiskNode? {
        if self.id == id { return self }
        for c in children { if let f = c.find(id) { return f } }
        return nil
    }
}

struct BootInfo: Sendable {
    var bootDevice: String          // e.g. disk3s1s1 (snapshot) or disk3s1
    var bootVolumeName: String
    var containerRef: String        // e.g. disk3
    var physicalStores: [String]    // e.g. [disk0s2]
    var physicalDisks: [String]     // e.g. [disk0]
    var volumeGroupID: String?
    var systemVolume: String?       // disk3s1
    var dataVolume: String?         // disk3s5
    var osVersion: String
    var osBuild: String
    var bootedFromSnapshot: Bool
    var sealed: Bool
    var fileVault: Bool
}

struct DiskScan: Sendable {
    var roots: [DiskNode]
    var boot: BootInfo
    var scannedAt: Date

    func find(_ id: String) -> DiskNode? {
        for r in roots { if let f = r.find(id) { return f } }
        return nil
    }
}

enum Bytes {
    static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        return f
    }()
    static func string(_ n: Int64?) -> String {
        guard let n else { return "—" }
        return formatter.string(fromByteCount: n)
    }
}
