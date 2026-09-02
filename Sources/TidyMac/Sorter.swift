//  "Sort Desktop & Downloads": moves loose files older than N days into typed folders
//  (Screenshots, Images, Documents, Installers, Archives, Videos, Music, Other) under a "Tidied"
//  folder in the same place. Files are moved, not trashed, and every move is written to a receipt,
//  so "put back" in What Tidy for Mac did restores the original layout exactly.

import SwiftUI
import Observation
import UniformTypeIdentifiers

struct SortMove: Identifiable, Sendable {
    var from: String
    var to: String
    var category: String
    var size: Int64
    var id: String { from }
}

enum Sorter {
    static let categories = ["Screenshots", "Images", "Documents", "Installers", "Archives", "Videos", "Music", "Other"]

    static func category(for url: URL) -> String {
        let name = url.lastPathComponent
        if name.hasPrefix("Screenshot") || name.hasPrefix("Screen Recording") { return "Screenshots" }
        let ext = url.pathExtension.lowercased()
        if ["dmg", "pkg", "mpkg", "iso", "xip"].contains(ext) { return "Installers" }
        if ["zip", "tar", "gz", "tgz", "bz2", "7z", "rar", "xz"].contains(ext) { return "Archives" }
        guard let type = UTType(filenameExtension: ext) else { return "Other" }
        if type.conforms(to: .image) { return "Images" }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return "Videos" }
        if type.conforms(to: .audio) { return "Music" }
        if type.conforms(to: .pdf) || type.conforms(to: .text) || type.conforms(to: .presentation) || type.conforms(to: .spreadsheet)
            || ["doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "rtf", "csv", "md"].contains(ext) { return "Documents" }
        return "Other"
    }

    /// Top-level files in each folder, untouched for `olderThanDays`, that aren't already sorted.
    static func plan(folders: [URL], olderThanDays: Int) -> [SortMove] {
        var out: [SortMove] = []
        let cutoff = Date().addingTimeInterval(-Double(olderThanDays) * 86400)
        for folder in folders {
            for u in Scanner.contents(folder) {
                let name = u.lastPathComponent
                if name.hasPrefix(".") || name == "Tidied" || u.pathExtension == "download" || u.pathExtension == "crdownload" || u.pathExtension == "part" { continue }
                guard let v = try? u.resourceValues(forKeys: [.isRegularFileKey, .isPackageKey, .contentModificationDateKey, .totalFileAllocatedSizeKey]),
                      v.isRegularFile == true || v.isPackage == true, let m = v.contentModificationDate, m < cutoff else { continue }
                if Protection.reason(for: u.path) != nil { continue }
                let cat = category(for: u)
                let dest = folder.appendingPathComponent("Tidied/\(cat)/\(name)")
                out.append(SortMove(from: u.path, to: dest.path, category: cat, size: Int64(v.totalFileAllocatedSize ?? 0)))
            }
        }
        return out.sorted { ($0.category, $0.from) < ($1.category, $1.from) }
    }

    /// Moves the files and returns the receipt. Never overwrites: a name clash gets " 2", " 3", …
    static func execute(_ moves: [SortMove]) -> TidySession {
        let fm = FileManager.default
        var records: [TidyRecord] = []
        for m in moves {
            var dest = URL(fileURLWithPath: m.to)
            try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            var n = 2
            while fm.fileExists(atPath: dest.path) {
                let base = URL(fileURLWithPath: m.to)
                dest = base.deletingLastPathComponent().appendingPathComponent("\(base.deletingPathExtension().lastPathComponent) \(n)").appendingPathExtension(base.pathExtension)
                n += 1
            }
            let ok = (try? fm.moveItem(atPath: m.from, toPath: dest.path)) != nil
            records.append(TidyRecord(id: UUID(), name: URL(fileURLWithPath: m.from).lastPathComponent, originalPath: m.from,
                                      trashPath: ok ? dest.path : nil, size: m.size, restored: false, kind: nil))
        }
        return TidySession(id: UUID(), date: Date(), automatic: false, label: String(localized: "Sorted Desktop & Downloads"), records: records)
    }
}

// MARK: - Model and window

@MainActor
@Observable
final class SorterModel {
    var desktop = true
    var downloads = true
    var days = 7
    var moves: [SortMove] = []
    var planning = false
    var done: TidySession?
    var demo = false

    var folders: [URL] {
        var f: [URL] = []
        if desktop { f.append(Scanner.home.appendingPathComponent("Desktop")) }
        if downloads { f.append(Scanner.home.appendingPathComponent("Downloads")) }
        return f
    }

    func plan() {
        guard !demo else { return }
        planning = true
        done = nil
        let folders = self.folders, days = self.days
        Task {
            moves = await Task.detached { Sorter.plan(folders: folders, olderThanDays: days) }.value
            planning = false
        }
    }

    func sort() {
        let m = moves
        Task {
            let s = await Task.detached { Sorter.execute(m) }.value
            History.shared.add(s)
            done = s
            moves = []
        }
    }

    var byCategory: [(String, [SortMove])] {
        Sorter.categories.compactMap { c in let ms = moves.filter { $0.category == c }; return ms.isEmpty ? nil : (c, ms) }
    }
    var totalBytes: Int64 { moves.reduce(0) { $0 + $1.size } }
}

struct SorterView: View {
    @State private var model: SorterModel
    @MainActor init(model: SorterModel? = nil) { _model = State(initialValue: model ?? SorterModel()) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Sort Desktop & Downloads").font(.title.weight(.bold))
                Text("Loose files get filed into folders by type inside a \"Tidied\" folder, right where they are. Nothing leaves the Desktop or Downloads, nothing is deleted, and What Tidy for Mac did can put every file back exactly where it was.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 16) {
                    Toggle("Desktop", isOn: $model.desktop)
                    Toggle("Downloads", isOn: $model.downloads)
                    Picker("Only files untouched for", selection: $model.days) {
                        Text("a week").tag(7); Text("a month").tag(30); Text("three months").tag(90)
                    }
                    .frame(maxWidth: 320)
                    Spacer()
                    Button("Preview") { model.plan() }.disabled(model.planning || model.folders.isEmpty)
                }
            }
            .padding(20)
            Divider()
            if let s = model.done {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 40)).foregroundStyle(Tidy.green)
                    Text("Filed \(s.movedCount) files").font(.title2.weight(.semibold))
                    Text("They're in the Tidied folders on your Desktop and in Downloads. To undo, open What Tidy for Mac did and choose Put everything back.").foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
                    Button("Preview again") { model.plan() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.planning {
                ProgressView("Looking…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.moves.isEmpty {
                ContentUnavailableView("Nothing to file", systemImage: "tray", description: Text("Click Preview to see what would be filed. Files you've touched recently are left alone."))
            } else {
                List {
                    ForEach(model.byCategory, id: \.0) { cat, ms in
                        Section("\(cat) · \(ms.count) files · \(Bytes.string(ms.reduce(0) { $0 + $1.size }))") {
                            ForEach(ms) { m in
                                HStack {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: m.from)).resizable().frame(width: 18, height: 18)
                                    Text(URL(fileURLWithPath: m.from).lastPathComponent).lineLimit(1)
                                    Text(URL(fileURLWithPath: m.from).deletingLastPathComponent().lastPathComponent).font(.caption).foregroundStyle(.tertiary)
                                    Spacer()
                                    Text(Bytes.string(m.size)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
            Divider()
            HStack {
                if !model.moves.isEmpty { Text("\(model.moves.count) files · \(Bytes.string(model.totalBytes))").font(.callout.weight(.semibold)) }
                Spacer()
                Button {
                    model.sort()
                } label: { Label("File them", systemImage: "folder.badge.gearshape").padding(.horizontal, 6) }
                    .buttonStyle(.borderedProminent).tint(Tidy.green).controlSize(.large)
                    .disabled(model.moves.isEmpty)
            }
            .padding(.horizontal, 20).padding(.vertical, 12).background(.bar)
        }
        .frame(minWidth: 720, minHeight: 520)
        .onAppear { if model.moves.isEmpty && model.done == nil { model.plan() } }
    }
}
