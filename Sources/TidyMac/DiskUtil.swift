//  Disk Map data source: wraps `diskutil list/apfs list/info -plist` and builds the tree
//  physical disk → partition → APFS container → volume → mounted snapshot, then marks the boot
//  path (what / is mounted from) and the System/Data volume group.

import Foundation

enum DiskUtilError: Error, CustomStringConvertible {
    case failed(String)
    var description: String {
        switch self { case .failed(let s): return s }
    }
}

/// Thin wrapper over /usr/sbin/diskutil's -plist output.
enum DiskUtil {

    static func run(_ args: [String]) throws -> [String: Any] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw DiskUtilError.failed("diskutil \(args.joined(separator: " ")) exited with status \(p.terminationStatus)")
        }
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw DiskUtilError.failed("diskutil \(args.joined(separator: " ")) returned an unreadable plist")
        }
        return plist
    }

    // diskutil reports some booleans as "Yes"/"No" strings.
    private static func flag(_ v: Any?) -> Bool {
        if let b = v as? Bool { return b }
        if let s = v as? String { return s.lowercased() == "yes" || s.lowercased() == "true" }
        if let n = v as? NSNumber { return n.boolValue }
        return false
    }

    private static func int64(_ v: Any?) -> Int64? {
        if let n = v as? NSNumber { return n.int64Value }
        return nil
    }

    private struct APFSVolumeInfo {
        var roles: [VolumeRole]
        var used: Int64?
        var encrypted: Bool
        var fileVault: Bool
        var locked: Bool
        var uuid: String?
    }

    private struct APFSContainerInfo {
        var ceiling: Int64?
        var free: Int64?
        var physicalStores: [String]
        var uuid: String?
    }

    static func scan() throws -> DiskScan {
        let list = try run(["list", "-plist"])
        let apfs = try run(["apfs", "list", "-plist"])
        let rootInfo = try run(["info", "-plist", "/"])
        let dataInfo = try? run(["info", "-plist", "/System/Volumes/Data"])

        // ---- APFS role / capacity lookups
        var volInfo: [String: APFSVolumeInfo] = [:]
        var contInfo: [String: APFSContainerInfo] = [:]
        for c in (apfs["Containers"] as? [[String: Any]]) ?? [] {
            let ref = c["ContainerReference"] as? String ?? ""
            let stores = ((c["PhysicalStores"] as? [[String: Any]]) ?? []).compactMap { $0["DeviceIdentifier"] as? String }
            contInfo[ref] = APFSContainerInfo(
                ceiling: int64(c["CapacityCeiling"]),
                free: int64(c["CapacityFree"]),
                physicalStores: stores,
                uuid: c["APFSContainerUUID"] as? String)
            for v in (c["Volumes"] as? [[String: Any]]) ?? [] {
                guard let dev = v["DeviceIdentifier"] as? String else { continue }
                let roles = ((v["Roles"] as? [String]) ?? []).map(VolumeRole.init(diskutil:))
                volInfo[dev] = APFSVolumeInfo(
                    roles: roles.isEmpty ? [.none] : roles,
                    used: int64(v["CapacityInUse"]),
                    encrypted: flag(v["Encryption"]),
                    fileVault: flag(v["FileVault"]),
                    locked: flag(v["Locked"]),
                    uuid: v["APFSVolumeUUID"] as? String)
            }
        }

        // ---- Boot facts
        let bootDevice = rootInfo["DeviceIdentifier"] as? String ?? "?"
        let bootContainer = rootInfo["APFSContainerReference"] as? String ?? ""
        let groupID = rootInfo["APFSVolumeGroupID"] as? String
        let dataDevice = dataInfo?["DeviceIdentifier"] as? String
        let bootStores = contInfo[bootContainer]?.physicalStores ?? []
        let bootDisks = Set(bootStores.map { wholeDisk(of: $0) })
        let bootedFromSnapshot = bootDevice.split(separator: "s").count >= 3   // diskNsMsK pattern
        // disk3s1s1 (snapshot) -> disk3s1 (the volume it belongs to)
        let systemVolume: String = {
            guard bootedFromSnapshot, let last = bootDevice.lastIndex(of: "s") else { return bootDevice }
            return String(bootDevice[..<last])
        }()

        let pi = ProcessInfo.processInfo
        let osv = pi.operatingSystemVersion
        let build = (try? String(contentsOfFile: "/System/Library/CoreServices/SystemVersion.plist", encoding: .utf8))
            .flatMap { s -> String? in
                guard let r = s.range(of: "<key>ProductBuildVersion</key>") else { return nil }
                let tail = s[r.upperBound...]
                guard let a = tail.range(of: "<string>"), let b = tail.range(of: "</string>") else { return nil }
                return String(tail[a.upperBound..<b.lowerBound])
            } ?? ""

        let boot = BootInfo(
            bootDevice: bootDevice,
            bootVolumeName: rootInfo["VolumeName"] as? String ?? "",
            containerRef: bootContainer,
            physicalStores: bootStores,
            physicalDisks: Array(bootDisks).sorted(),
            volumeGroupID: groupID,
            systemVolume: systemVolume,
            dataVolume: dataDevice,
            osVersion: "\(osv.majorVersion).\(osv.minorVersion).\(osv.patchVersion)",
            osBuild: build,
            bootedFromSnapshot: bootedFromSnapshot,
            sealed: flag(rootInfo["Sealed"]),
            fileVault: flag(rootInfo["FileVault"]))

        // ---- Volume-group membership for volumes in the boot container (one diskutil info per volume)
        var groupOf: [String: String] = [:]
        var sealedOf: [String: Bool] = [:]
        let entries = (list["AllDisksAndPartitions"] as? [[String: Any]]) ?? []
        if let bc = entries.first(where: { ($0["DeviceIdentifier"] as? String) == bootContainer }) {
            for v in (bc["APFSVolumes"] as? [[String: Any]]) ?? [] {
                guard let dev = v["DeviceIdentifier"] as? String else { continue }
                if let info = try? run(["info", "-plist", dev]) {
                    groupOf[dev] = info["APFSVolumeGroupID"] as? String
                    sealedOf[dev] = flag(info["Sealed"])
                }
            }
        }

        // ---- Build container nodes
        var containers: [String: DiskNode] = [:]
        for e in entries where (e["Content"] as? String) == "Apple_APFS_Container" {
            guard let dev = e["DeviceIdentifier"] as? String else { continue }
            let ci = contInfo[dev]
            let stores = ((e["APFSPhysicalStores"] as? [[String: Any]]) ?? []).compactMap { $0["DeviceIdentifier"] as? String }
            let isBootC = dev == bootContainer
            var node = DiskNode(
                id: dev, kind: .container, name: "Container \(dev)", deviceIdentifier: dev,
                content: "Apple_APFS_Container", size: int64(e["Size"]) ?? ci?.ceiling ?? 0,
                used: (ci?.ceiling).flatMap { c in (ci?.free).map { c - $0 } },
                free: ci?.free, mountPoint: nil, roles: [],
                isInternal: flag(e["OSInternal"]), onBootPath: isBootC,
                physicalStores: stores.isEmpty ? (ci?.physicalStores ?? []) : stores,
                uuid: ci?.uuid)

            for v in (e["APFSVolumes"] as? [[String: Any]]) ?? [] {
                guard let vdev = v["DeviceIdentifier"] as? String else { continue }
                // diskutil lists a mounted snapshot (diskNsMsK) as if it were a volume; it is shown under its parent instead.
                if vdev.dropFirst(4).filter({ $0 == "s" }).count >= 2 { continue }
                let vi = volInfo[vdev]
                let inGroup = groupID != nil && groupOf[vdev] == groupID
                var vol = DiskNode(
                    id: vdev, kind: .volume, name: v["VolumeName"] as? String ?? "(unnamed)",
                    deviceIdentifier: vdev, content: "APFS", size: int64(v["Size"]) ?? 0,
                    used: vi?.used, free: nil, mountPoint: v["MountPoint"] as? String,
                    roles: vi?.roles ?? [.none], isInternal: flag(e["OSInternal"]),
                    isBootDevice: vdev == bootDevice,
                    onBootPath: isBootC && (vdev == bootDevice || vdev == systemVolume || vdev == dataDevice || inGroup),
                    inBootVolumeGroup: inGroup,
                    sealed: sealedOf[vdev] ?? false,
                    encrypted: vi?.encrypted ?? false, fileVault: vi?.fileVault ?? false,
                    locked: vi?.locked ?? false, uuid: vi?.uuid)

                for s in (v["MountedSnapshots"] as? [[String: Any]]) ?? [] {
                    let sdev = s["SnapshotBSD"] as? String ?? s["SnapshotUUID"] as? String ?? UUID().uuidString
                    let snapName = s["SnapshotName"] as? String ?? "snapshot"
                    let snap = DiskNode(
                        id: sdev, kind: .snapshot, name: "System snapshot",
                        deviceIdentifier: sdev, content: snapName, size: vol.size,
                        used: vol.used, free: nil, mountPoint: s["SnapshotMountPoint"] as? String,
                        roles: vol.roles, isInternal: vol.isInternal,
                        isBootDevice: sdev == bootDevice, onBootPath: sdev == bootDevice,
                        inBootVolumeGroup: inGroup, sealed: flag(s["Sealed"]),
                        encrypted: vol.encrypted, fileVault: vol.fileVault, uuid: s["SnapshotUUID"] as? String)
                    vol.children.append(snap)
                    if snap.onBootPath { vol.onBootPath = true }
                }
                node.children.append(vol)
            }
            node.children.sort { $0.deviceIdentifier.localizedStandardCompare($1.deviceIdentifier) == .orderedAscending }
            containers[dev] = node
        }

        // ---- Build physical disks, attaching containers under their physical-store partitions
        var roots: [DiskNode] = []
        var attached = Set<String>()
        for e in entries where (e["Content"] as? String) != "Apple_APFS_Container" {
            guard let dev = e["DeviceIdentifier"] as? String else { continue }
            // OSInternal means "hidden OS disk", not physical location; ask diskutil info for the real facts.
            let dinfo = (try? run(["info", "-plist", dev])) ?? [:]
            let internalDisk = flag(dinfo["Internal"])
            let media = dinfo["MediaName"] as? String ?? dev
            var kindBits: [String] = []
            if let bus = dinfo["BusProtocol"] as? String { kindBits.append(bus) }
            if dinfo["SolidState"] != nil { kindBits.append(flag(dinfo["SolidState"]) ? "SSD" : "HDD") }
            if flag(dinfo["Removable"]) { kindBits.append("removable") }
            kindBits.append(e["Content"] as? String ?? "")
            var disk = DiskNode(
                id: dev, kind: .physicalDisk, name: media, deviceIdentifier: dev,
                content: kindBits.filter { !$0.isEmpty }.joined(separator: " · "), size: int64(e["Size"]) ?? 0,
                used: nil, free: nil, mountPoint: e["MountPoint"] as? String, roles: [],
                isInternal: internalDisk, onBootPath: bootDisks.contains(dev))
            for p in (e["Partitions"] as? [[String: Any]]) ?? [] {
                guard let pdev = p["DeviceIdentifier"] as? String else { continue }
                var part = DiskNode(
                    id: pdev, kind: .partition,
                    name: p["VolumeName"] as? String ?? (p["Content"] as? String ?? pdev),
                    deviceIdentifier: pdev, content: p["Content"] as? String ?? "",
                    size: int64(p["Size"]) ?? 0, used: nil, free: nil,
                    mountPoint: p["MountPoint"] as? String, roles: [], isInternal: internalDisk,
                    onBootPath: bootStores.contains(pdev), uuid: p["DiskUUID"] as? String)
                for (cdev, c) in containers where c.physicalStores.contains(pdev) {
                    part.children.append(setInternal(c, internalDisk))
                    attached.insert(cdev)
                }
                disk.children.append(part)
            }
            if disk.children.isEmpty, let name = e["VolumeName"] as? String { disk.name = name }
            roots.append(disk)
        }
        // Containers with no visible physical store (disk images, etc.) become roots.
        for (cdev, c) in containers where !attached.contains(cdev) { roots.append(c) }
        roots.sort { $0.deviceIdentifier.localizedStandardCompare($1.deviceIdentifier) == .orderedAscending }

        return DiskScan(roots: roots, boot: boot, scannedAt: Date())
    }

    private static func setInternal(_ n: DiskNode, _ v: Bool) -> DiskNode {
        var m = n
        m.isInternal = v
        m.children = n.children.map { setInternal($0, v) }
        return m
    }

    /// disk3s1s1 -> disk3, disk0s2 -> disk0
    static func wholeDisk(of id: String) -> String {
        guard id.hasPrefix("disk") else { return id }
        let afterDisk = id.index(id.startIndex, offsetBy: 4)
        if let firstS = id[afterDisk...].firstIndex(of: "s") { return String(id[..<firstS]) }
        return id
    }
}
