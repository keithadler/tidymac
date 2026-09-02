//  Disk Map window (the advanced view): boot-path strip, colour-coded tree with usage bars,
//  and a detail pane. Kept from the app's origins as a boot-volume mapper.

import SwiftUI

struct ContentView: View {
    @Bindable var model: ScanModel

    var body: some View {
        VStack(spacing: 0) {
            if let scan = model.scan {
                BootHeader(boot: scan.boot, scan: scan, selection: $model.selection)
                Divider()
                HSplitView {
                    TreePane(scan: scan, selection: $model.selection)
                        .frame(minWidth: 640, idealWidth: 820)
                    DetailPane(node: model.selectedNode, scan: scan)
                        .frame(minWidth: 320, idealWidth: 380)
                }
                Divider()
                Legend()
            } else if let err = model.error {
                ContentUnavailableView("Could not read disk layout", systemImage: "exclamationmark.triangle",
                                       description: Text(err))
            } else {
                ProgressView("Reading disk layout…").padding(40)
            }
        }
        .frame(minWidth: 1000, minHeight: 640)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { model.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .disabled(model.loading)
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
        .onAppear { if model.scan == nil { model.refresh() } }
    }
}

// MARK: - Header: what is booted and the path to it

struct BootHeader: View {
    let boot: BootInfo
    let scan: DiskScan
    @Binding var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "apple.logo").font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("macOS \(boot.osVersion) \(boot.osBuild.isEmpty ? "" : "(\(boot.osBuild))")")
                        .font(.title3.weight(.semibold))
                    Text("Booted from \(boot.bootVolumeName) · \(boot.bootDevice)\(boot.bootedFromSnapshot ? " · sealed system snapshot" : "")")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 6) {
                    Badge(text: boot.sealed ? "Sealed" : "Unsealed", color: boot.sealed ? Theme.color(for: .system) : .orange)
                    Badge(text: boot.fileVault ? "FileVault on" : "FileVault off", color: boot.fileVault ? Theme.color(for: .data) : .secondary)
                }
                Text("Scanned \(scan.scannedAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            BootPathStrip(boot: boot, scan: scan, selection: $selection)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.bar)
    }
}

struct BootPathStrip: View {
    let boot: BootInfo
    let scan: DiskScan
    @Binding var selection: String?

    private var chain: [DiskNode] {
        var ids: [String] = []
        ids.append(contentsOf: boot.physicalDisks)
        ids.append(contentsOf: boot.physicalStores)
        ids.append(boot.containerRef)
        if let s = boot.systemVolume, s != boot.bootDevice { ids.append(s) }
        ids.append(boot.bootDevice)
        return ids.compactMap { scan.find($0) }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text("Boot path").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(Array(chain.enumerated()), id: \.element.id) { i, n in
                    if i > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                    Button { selection = n.id } label: {
                        HStack(spacing: 5) {
                            Circle().fill(Theme.color(for: n)).frame(width: 8, height: 8)
                            Text(n.kind == .snapshot ? "snapshot" : n.name).font(.caption)
                            Text(n.deviceIdentifier).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(selection == n.id ? Theme.color(for: n).opacity(0.18) : Color.primary.opacity(0.05),
                                    in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                Text("/").font(.caption.monospaced().weight(.bold))
                if let d = boot.dataVolume, let dn = scan.find(d) {
                    Text("+").font(.caption).foregroundStyle(.tertiary)
                    Button { selection = dn.id } label: {
                        HStack(spacing: 5) {
                            Circle().fill(Theme.color(for: dn)).frame(width: 8, height: 8)
                            Text(dn.name).font(.caption)
                            Text(dn.deviceIdentifier).font(.caption.monospaced()).foregroundStyle(.secondary)
                            Text("→ /System/Volumes/Data").font(.caption2.monospaced()).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(selection == dn.id ? Theme.color(for: dn).opacity(0.18) : Color.primary.opacity(0.05),
                                    in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Tree

struct TreePane: View {
    let scan: DiskScan
    @Binding var selection: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(scan.roots) { root in
                    ForEach(root.flattened(), id: \.node.id) { item in
                        NodeRow(node: item.node, depth: item.depth, selected: selection == item.node.id)
                            .contentShape(Rectangle())
                            .onTapGesture { selection = item.node.id }
                    }
                    Divider().padding(.vertical, 6)
                }
            }
            .padding(12)
        }
    }
}

struct NodeRow: View {
    let node: DiskNode
    let depth: Int
    let selected: Bool

    private var color: Color { Theme.color(for: node) }

    var body: some View {
        HStack(spacing: 8) {
            // Tree guide lines
            HStack(spacing: 0) {
                ForEach(0..<depth, id: \.self) { _ in
                    Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1).padding(.horizontal, 9)
                }
            }
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 5, height: 24)
            Image(systemName: Theme.glyph(for: node))
                .foregroundStyle(color).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(node.name).font(.body.weight(node.onBootPath ? .semibold : .regular))
                        .lineLimit(1).fixedSize(horizontal: true, vertical: false).layoutPriority(2)
                    Text(node.deviceIdentifier).font(.caption.monospaced()).foregroundStyle(.secondary)
                        .fixedSize().layoutPriority(1)
                    if node.isBootDevice { Badge(text: "BOOTED /", color: color, strong: true) }
                    else if node.inBootVolumeGroup && node.kind == .volume { Badge(text: "boot group", color: color) }
                    else if node.onBootPath { Badge(text: "boot path", color: color) }
                    if node.sealed { Badge(text: "sealed", color: Theme.color(for: .system)) }
                    if node.fileVault { Badge(text: "FileVault", color: Theme.color(for: .data)) }
                    else if node.encrypted { Badge(text: "encrypted", color: .secondary) }
                    if node.locked { Badge(text: "locked", color: .red) }
                }
                HStack(spacing: 6) {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if node.kind == .container { UsageBar(container: node).frame(width: 140, height: 10) }
            Text(sizeText).font(.caption.monospaced()).foregroundStyle(.secondary)
                .fixedSize().frame(minWidth: 96, alignment: .trailing)
        }
        .padding(.vertical, 4).padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selected ? color.opacity(0.22) : (node.onBootPath ? color.opacity(0.07) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(selected ? color.opacity(0.8) : Color.clear, lineWidth: 1)
        )
    }

    private var subtitle: String {
        var parts: [String] = []
        switch node.kind {
        case .physicalDisk: parts.append(node.isInternal ? "Internal · \(node.content)" : "External · \(node.content)")
        case .partition:    parts.append(node.content)
        case .container:    parts.append("Physical store \(node.physicalStores.joined(separator: ", "))")
        case .volume:       parts.append(node.roles.map(\.rawValue).joined(separator: ", "))
        case .snapshot:     parts.append(node.content)
        }
        if let m = node.mountPoint, !m.isEmpty { parts.append("mounted at \(m)") }
        else if node.kind == .volume { parts.append("not mounted") }
        return parts.joined(separator: " · ")
    }

    private var sizeText: String {
        switch node.kind {
        case .volume, .snapshot:
            if let u = node.used { return "\(Bytes.string(u)) used" }
            return Bytes.string(node.size)
        case .container:
            if let f = node.free { return "\(Bytes.string(f)) free" }
            return Bytes.string(node.size)
        default: return Bytes.string(node.size)
        }
    }
}

/// Proportional usage of an APFS container, colored by the role of each volume.
struct UsageBar: View {
    let container: DiskNode

    var body: some View {
        GeometryReader { geo in
            let total = max(Double(container.size), 1)
            HStack(spacing: 1) {
                ForEach(container.children.filter { ($0.used ?? 0) > 0 }.sorted { ($0.used ?? 0) > ($1.used ?? 0) }) { v in
                    Rectangle().fill(Theme.color(for: v))
                        .frame(width: max(2, geo.size.width * Double(v.used ?? 0) / total))
                        .help("\(v.name): \(Bytes.string(v.used))")
                }
                Rectangle().fill(Color.primary.opacity(0.08))
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }
}

// MARK: - Detail

struct DetailPane: View {
    let node: DiskNode?
    let scan: DiskScan

    var body: some View {
        ScrollView {
            if let n = node {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 8).fill(Theme.color(for: n)).frame(width: 40, height: 40)
                            .overlay(Image(systemName: Theme.glyph(for: n)).foregroundStyle(.white).font(.title3))
                        VStack(alignment: .leading) {
                            Text(n.name).font(.title3.weight(.semibold)).lineLimit(2)
                            Text(n.kind.rawValue).foregroundStyle(.secondary)
                        }
                    }
                    if n.isBootDevice {
                        Callout(color: Theme.color(for: n),
                                text: "This is what macOS is running from right now. It is mounted at / and cannot be modified while booted.")
                    } else if n.inBootVolumeGroup, n.primaryRole == .data {
                        Callout(color: Theme.color(for: n),
                                text: "Data half of the running system's volume group. Mounted at /System/Volumes/Data and firmlinked into /.")
                    } else if n.onBootPath {
                        Callout(color: Theme.color(for: n), text: "Part of the path from hardware to the running OS.")
                    }
                    if let r = n.primaryRole, n.kind == .volume || n.kind == .snapshot {
                        Text(r.explanation).font(.callout).foregroundStyle(.secondary)
                    }
                    if n.kind == .container {
                        VStack(alignment: .leading, spacing: 6) {
                            UsageBar(container: n).frame(height: 14)
                            ForEach(n.children.sorted { ($0.used ?? 0) > ($1.used ?? 0) }) { v in
                                HStack {
                                    Circle().fill(Theme.color(for: v)).frame(width: 8, height: 8)
                                    Text(v.name).font(.caption)
                                    Spacer()
                                    Text(Bytes.string(v.used)).font(.caption.monospaced()).foregroundStyle(.secondary)
                                }
                            }
                            HStack {
                                Circle().fill(Color.primary.opacity(0.15)).frame(width: 8, height: 8)
                                Text("Free").font(.caption)
                                Spacer()
                                Text(Bytes.string(n.free)).font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                        .padding(10).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    }
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                        row("Device", n.deviceIdentifier, mono: true)
                        row("Node", "/dev/\(n.deviceIdentifier)", mono: true)
                        row("Type", n.content)
                        if !n.roles.isEmpty { row("Roles", n.roles.map(\.rawValue).joined(separator: ", ")) }
                        row("Size", Bytes.string(n.size))
                        if let u = n.used { row("Used", Bytes.string(u)) }
                        if let f = n.free { row("Free", Bytes.string(f)) }
                        row("Mount point", n.mountPoint?.isEmpty == false ? n.mountPoint! : "—", mono: true)
                        if !n.physicalStores.isEmpty { row("Physical store", n.physicalStores.joined(separator: ", "), mono: true) }
                        if let u = n.uuid { row("UUID", u, mono: true) }
                        row("Location", n.isInternal ? "Internal" : "External")
                        if n.kind == .volume || n.kind == .snapshot {
                            row("Sealed", n.sealed ? "Yes" : "No")
                            row("Encrypted", n.encrypted ? (n.fileVault ? "Yes (FileVault)" : "Yes") : "No")
                            row("Volume group", n.inBootVolumeGroup ? "Boot volume group" : "—")
                        }
                        if !n.children.isEmpty { row("Contains", "\(n.children.count) \(n.children.count == 1 ? "item" : "items")") }
                    }
                    .font(.callout)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ContentUnavailableView("Select an item", systemImage: "cursorarrow.click")
                    .padding(40)
            }
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String, mono: Bool = false) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).font(mono ? .callout.monospaced() : .callout).textSelection(.enabled)
        }
    }
}

// MARK: - Bits

struct Badge: View {
    let text: String
    let color: Color
    var strong: Bool = false
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold)).lineLimit(1).fixedSize()
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(strong ? color : color.opacity(0.15), in: Capsule())
            .foregroundStyle(strong ? .white : color)
    }
}

struct Callout: View {
    let color: Color
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4)
            Text(text).font(.callout)
        }
        .padding(10).background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct Legend: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(Theme.legend, id: \.label) { item in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(item.color).frame(width: 10, height: 10)
                        Text(item.label).font(.caption)
                    }
                }
                Divider().frame(height: 12)
                Badge(text: "BOOTED  /", color: Theme.color(for: .system), strong: true)
                Text("= mounted as root").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .background(.bar)
    }
}
