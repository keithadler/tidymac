//  Space Map: a squarified treemap of the home folder. SpaceBuilder measures three levels deep
//  and folds the long tail into one "smaller items" block. Treemap.layout is the Bruls /
//  Huizing / van Wijk algorithm. Double-click zooms in, right-click reveals in Finder.

import SwiftUI
import Observation

// MARK: - Data

struct SpaceNode: Identifiable, Sendable {
    let id: String          // full path
    let name: String
    let size: Int64
    let isDirectory: Bool
    var children: [SpaceNode]
}

enum SpaceBuilder {
    /// Sizes the home folder three levels deep. Deeper folders are measured but not expanded.
    static func build(_ url: URL, depth: Int = 0, maxDepth: Int = 3) -> SpaceNode {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .totalFileAllocatedSizeKey, .isRegularFileKey]
        guard depth < maxDepth,
              let entries = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(keys), options: []) else {
            return SpaceNode(id: url.path, name: url.lastPathComponent, size: Scanner.size(of: url), isDirectory: true, children: [])
        }
        var children: [SpaceNode] = []
        for e in entries {
            guard let v = try? e.resourceValues(forKeys: keys), v.isSymbolicLink != true else { continue }
            if v.isDirectory == true && v.isPackage != true {
                children.append(build(e, depth: depth + 1, maxDepth: maxDepth))
            } else if v.isDirectory == true {
                children.append(SpaceNode(id: e.path, name: e.lastPathComponent, size: Scanner.size(of: e), isDirectory: false, children: []))
            } else if v.isRegularFile == true {
                children.append(SpaceNode(id: e.path, name: e.lastPathComponent, size: Int64(v.totalFileAllocatedSize ?? 0), isDirectory: false, children: []))
            }
        }
        children.sort { $0.size > $1.size }
        let total = children.reduce(0) { $0 + $1.size }
        // Fold the long tail into one "everything else" block so the map stays readable.
        let threshold = max(total / 200, 1_000_000)
        let big = children.filter { $0.size >= threshold }
        let rest = children.filter { $0.size < threshold }
        if rest.count > 1 {
            let restSize = rest.reduce(0) { $0 + $1.size }
            if restSize > 0 {
                children = big + [SpaceNode(id: url.path + "/…", name: String(localized: "\(rest.count) smaller items"), size: restSize, isDirectory: false, children: [])]
            } else { children = big }
        }
        return SpaceNode(id: url.path, name: url.lastPathComponent, size: total, isDirectory: true, children: children)
    }
}

// MARK: - Squarified treemap layout (Bruls, Huizing, van Wijk)

enum Treemap {
    /// Lays items out largest-first, adding each to the current row while doing so keeps the row's
    /// worst aspect ratio from getting worse; when it would, the row is placed against the shorter
    /// side of the remaining rectangle and a new row starts. Result: blocks that stay close to
    /// square, so labels fit and areas are easy to compare by eye.
    static func layout(_ items: [SpaceNode], in bounds: CGRect) -> [(SpaceNode, CGRect)] {
        let items = items.filter { $0.size > 0 }
        let total = items.reduce(0.0) { $0 + Double($1.size) }
        guard total > 0, bounds.width > 1, bounds.height > 1 else { return [] }
        let scale = Double(bounds.width * bounds.height) / total
        let areas = items.map { Double($0.size) * scale }
        var result: [(SpaceNode, CGRect)] = []
        var rect = bounds
        var row: [Int] = []
        var i = 0

        func worst(_ r: [Int], _ w: Double) -> Double {
            let s = r.reduce(0.0) { $0 + areas[$1] }
            guard s > 0, w > 0 else { return .infinity }
            let mx = r.map { areas[$0] }.max() ?? 0
            let mn = r.map { areas[$0] }.min() ?? 0
            guard mn > 0 else { return .infinity }
            return max(w * w * mx / (s * s), s * s / (w * w * mn))
        }

        func place(_ r: [Int]) {
            let s = r.reduce(0.0) { $0 + areas[$1] }
            guard s > 0 else { return }
            if rect.width >= rect.height {
                let w = CGFloat(s) / max(rect.height, 1)
                var y = rect.minY
                for j in r {
                    let h = CGFloat(areas[j]) / max(w, 0.0001)
                    result.append((items[j], CGRect(x: rect.minX, y: y, width: w, height: h)))
                    y += h
                }
                rect = CGRect(x: rect.minX + w, y: rect.minY, width: max(0, rect.width - w), height: rect.height)
            } else {
                let h = CGFloat(s) / max(rect.width, 1)
                var x = rect.minX
                for j in r {
                    let w = CGFloat(areas[j]) / max(h, 0.0001)
                    result.append((items[j], CGRect(x: x, y: rect.minY, width: w, height: h)))
                    x += w
                }
                rect = CGRect(x: rect.minX, y: rect.minY + h, width: rect.width, height: max(0, rect.height - h))
            }
        }

        while i < items.count {
            let w = Double(min(rect.width, rect.height))
            if row.isEmpty || worst(row, w) >= worst(row + [i], w) {
                row.append(i); i += 1
            } else {
                place(row); row = []
            }
        }
        if !row.isEmpty { place(row) }
        return result
    }
}

// MARK: - Model

@MainActor
@Observable
final class SpaceModel {
    var root: SpaceNode?
    var demo = false
    var path: [SpaceNode] = []      // zoom stack, root first
    var loading = false
    var hovered: String?

    var current: SpaceNode? { path.last ?? root }

    func build() {
        guard !loading, !demo else { return }
        loading = true
        Task {
            let r = await Task.detached(priority: .userInitiated) { SpaceBuilder.build(Scanner.home) }.value
            root = r
            path = [r]
            loading = false
        }
    }

    func zoom(into n: SpaceNode) { if n.isDirectory, !n.children.isEmpty { path.append(n) } }
    func up() { if path.count > 1 { path.removeLast() } }
    func jump(to index: Int) { if index < path.count { path = Array(path.prefix(index + 1)) } }
}

// MARK: - View

struct SpaceMapView: View {
    @State private var model: SpaceModel

    @MainActor init(model: SpaceModel? = nil) { _model = State(initialValue: model ?? SpaceModel()) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { model.up() } label: { Label("Up", systemImage: "arrow.up") }
                    .disabled(model.path.count <= 1)
                    .keyboardShortcut(.upArrow, modifiers: .command)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(model.path.enumerated()), id: \.element.id) { i, n in
                            if i > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                            Button(i == 0 ? String(localized: "Home") : n.name) { model.jump(to: i) }.buttonStyle(.plain)
                                .fontWeight(i == model.path.count - 1 ? .semibold : .regular)
                        }
                    }
                }
                Spacer()
                if let c = model.current {
                    Text(Bytes.string(c.size)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: c.id)]) } label: {
                        Label("Show in Finder", systemImage: "magnifyingglass")
                    }
                }
                Button { model.build() } label: { Label("Rescan", systemImage: "arrow.clockwise") }.disabled(model.loading)
            }
            .padding(12)
            Divider()
            ZStack {
                if let c = model.current, !model.loading {
                    GeometryReader { geo in
                        let rects = Treemap.layout(c.children, in: CGRect(origin: .zero, size: geo.size).insetBy(dx: 2, dy: 2))
                        ForEach(Array(rects.enumerated()), id: \.element.0.id) { idx, pair in
                            let (node, r) = pair
                            Block(node: node, rect: r, color: Tidy.mapPalette[idx % Tidy.mapPalette.count],
                                  hovered: model.hovered == node.id, total: c.size)
                                .onHover { model.hovered = $0 ? node.id : (model.hovered == node.id ? nil : model.hovered) }
                                .onTapGesture(count: 2) { model.zoom(into: node) }
                                .contextMenu {
                                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: node.id)]) }
                                    if node.isDirectory && !node.children.isEmpty { Button("Zoom in") { model.zoom(into: node) } }
                                }
                        }
                    }
                    .padding(6)
                } else {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Measuring your home folder…").foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            HStack {
                Text("Bigger blocks take more space. Double-click a folder to look inside. Right-click for Finder.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let h = model.hovered, let c = model.current, let n = c.children.first(where: { $0.id == h }) {
                    Text("\(n.name) · \(Bytes.string(n.size))").font(.caption.monospacedDigit())
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8).background(.bar)
        }
        .frame(minWidth: 800, minHeight: 560)
        .onAppear { if model.root == nil { model.build() } }
    }
}

struct Block: View {
    let node: SpaceNode
    let rect: CGRect
    let color: Color
    let hovered: Bool
    let total: Int64

    private var fraction: Double { total > 0 ? Double(node.size) / Double(total) : 0 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(hovered ? 0.95 : 0.78))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
            if rect.width > 56 && rect.height > 30 {
                VStack(alignment: .leading, spacing: 1) {
                    Text(node.name).font(.caption.weight(.semibold)).lineLimit(1)
                    if rect.height > 44 {
                        Text("\(Bytes.string(node.size)) · \(Int(fraction * 100))%").font(.caption2).lineLimit(1)
                    }
                }
                .foregroundStyle(.white)
                .padding(6)
                .frame(maxWidth: rect.width, alignment: .leading)
            }
        }
        .frame(width: max(1, rect.width), height: max(1, rect.height))
        .position(x: rect.midX, y: rect.midY)
        .help("\(node.name): \(Bytes.string(node.size))")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(node.name), \(Bytes.string(node.size)), \(Int(fraction * 100)) percent"))
    }
}
