//  Text printer for the disk map, used by `tidy disk`. The rest of the command line lives in CLI.swift.

import Foundation

/// `TidyMac --dump` prints the same map as plain text and exits. Handy for scripts and for checking the parser.
enum Dump {
    /// Prints the disk map as text. Used by `tidy disk`.
    static func printDiskMap(_ scan: DiskScan) {
        let b = scan.boot
        print("macOS \(b.osVersion) \(b.osBuild)  booted from \(b.bootVolumeName) (\(b.bootDevice))\(b.bootedFromSnapshot ? " via sealed snapshot" : "")")
        print("boot path: \(b.physicalDisks.joined(separator: ",")) -> \(b.physicalStores.joined(separator: ",")) -> \(b.containerRef) -> \(b.systemVolume ?? "?") -> \(b.bootDevice) -> /   data: \(b.dataVolume ?? "?")")
        print("sealed: \(b.sealed)  filevault: \(b.fileVault)  volume group: \(b.volumeGroupID ?? "-")")
        print()
        for r in scan.roots {
            for (n, d) in r.flattened() {
                var tags: [String] = []
                if n.isBootDevice { tags.append("BOOTED /") }
                else if n.inBootVolumeGroup { tags.append("boot-group") }
                else if n.onBootPath { tags.append("boot-path") }
                if n.sealed { tags.append("sealed") }
                if n.fileVault { tags.append("filevault") } else if n.encrypted { tags.append("encrypted") }
                let roles = n.roles.isEmpty ? "" : " [" + n.roles.map(\.rawValue).joined(separator: ",") + "]"
                let mount = (n.mountPoint?.isEmpty == false) ? "  @ \(n.mountPoint!)" : ""
                let size = n.kind == .container ? "\(Bytes.string(n.free)) free of \(Bytes.string(n.size))"
                         : (n.used != nil ? "\(Bytes.string(n.used)) used" : Bytes.string(n.size))
                print(String(repeating: "  ", count: d) + "\(n.kind.rawValue.padding(toLength: 15, withPad: " ", startingAt: 0)) \(n.deviceIdentifier.padding(toLength: 10, withPad: " ", startingAt: 0)) \(n.name)\(roles)  \(size)\(mount)\(tags.isEmpty ? "" : "  <" + tags.joined(separator: ", ") + ">")")
            }
            print()
        }
    }
}
