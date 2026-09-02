//  App uninstaller: pick an app (or drop one in), find everything it owns via
//  Scanner.relatedFiles, quit it if running, and move the app plus its files to the Trash with a
//  receipt. Apple's own apps are excluded from the list.

import SwiftUI
import Observation

@MainActor
@Observable
final class UninstallModel {
    static let shared = UninstallModel()

    struct AppEntry: Identifiable {
        var path: String
        var name: String
        var bundleID: String?
        var size: Int64?
        var icon: NSImage
        var id: String { path }
    }

    enum Phase: Equatable {
        case idle, finding, working(done: Int, total: Int), done(moved: Int, size: Int64, failed: Int), failed(String)
    }

    var apps: [AppEntry] = []
    var search = ""
    var selected: AppEntry?
    var related: [CleanItem] = []
    var phase: Phase = .idle
    var loaded = false

    var filtered: [AppEntry] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? apps : apps.filter { $0.name.lowercased().contains(q) }
    }
    var selectedRelated: [CleanItem] { related.filter { $0.selected && !$0.isProtected } }
    var totalToRemove: Int64 { (selected?.size ?? 0) + selectedRelated.reduce(0) { $0 + $1.size } }

    func load() {
        guard !loaded else { return }
        loaded = true
        let dirs = ["/Applications", "/Applications/Utilities", Scanner.home.appendingPathComponent("Applications").path]
        var found: [AppEntry] = []
        for d in dirs {
            for u in Scanner.contents(URL(fileURLWithPath: d)) where u.pathExtension == "app" {
                let bid = Bundle(url: u)?.bundleIdentifier
                if let bid, bid.hasPrefix("com.apple.") { continue }   // system apps are not ours to remove
                found.append(AppEntry(path: u.path, name: u.deletingPathExtension().lastPathComponent, bundleID: bid,
                                      size: nil, icon: NSWorkspace.shared.icon(forFile: u.path)))
            }
        }
        apps = found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        Task {
            for i in apps.indices {
                let p = apps[i].path
                let s = await Task.detached { Scanner.size(of: URL(fileURLWithPath: p)) }.value
                if i < apps.count, apps[i].path == p { apps[i].size = s }
            }
        }
    }

    /// Selects an app dropped onto a window, adding it to the list if it lives somewhere unusual.
    func pick(_ url: URL) {
        load()
        if let e = apps.first(where: { $0.path == url.path }) { select(e); return }
        let e = AppEntry(path: url.path, name: url.deletingPathExtension().lastPathComponent,
                         bundleID: Bundle(url: url)?.bundleIdentifier, size: nil, icon: NSWorkspace.shared.icon(forFile: url.path))
        apps.insert(e, at: 0)
        select(e)
    }

    func select(_ app: AppEntry) {
        selected = app
        related = []
        phase = .finding
        let path = app.path, bid = app.bundleID, name = app.name
        Task {
            let r = await Task.detached { Scanner.relatedFiles(appPath: path, bundleID: bid, appName: name) }.value
            if selected?.path == path { related = r; phase = .idle }
        }
    }

    func toggle(_ id: String) {
        if let i = related.firstIndex(where: { $0.id == id }), !related[i].isProtected { related[i].selected.toggle() }
    }

    func uninstall() {
        guard let app = selected else { return }
        let items = selectedRelated
        let paths = [app.path] + items.flatMap(\.paths)
        phase = .working(done: 0, total: paths.count)
        Task {
            if let bid = app.bundleID {
                for r in NSRunningApplication.runningApplications(withBundleIdentifier: bid) { r.terminate() }
                try? await Task.sleep(for: .seconds(1))
            }
            var records: [TidyRecord] = []
            var done = 0
            let appSize = app.size ?? 0
            let appTrash = await Task.detached { Scanner.moveToTrash(app.path) }.value
            records.append(TidyRecord(id: UUID(), name: app.name, originalPath: app.path, trashPath: appTrash, size: appSize, restored: false, kind: nil))
            done += 1; phase = .working(done: done, total: paths.count)
            for item in items {
                for p in item.paths {
                    let t = await Task.detached { Scanner.moveToTrash(p) }.value
                    records.append(TidyRecord(id: UUID(), name: item.name, originalPath: p, trashPath: t, size: item.size, restored: false, kind: .leftovers))
                    done += 1; phase = .working(done: done, total: paths.count)
                }
            }
            let session = TidySession(id: UUID(), date: Date(), automatic: false,
                                      label: String(localized: "Uninstalled \(app.name)"), records: records)
            History.shared.add(session)
            if appTrash == nil {
                phase = .failed(String(localized: "macOS wouldn't let Tidy for Mac move \(app.name) to the Trash. It may need an administrator, or it may be managed by your school or workplace."))
            } else {
                phase = .done(moved: session.movedCount, size: session.totalSize, failed: session.failedCount)
                apps.removeAll { $0.path == app.path }
            }
        }
    }

    func reset() {
        selected = nil
        related = []
        phase = .idle
    }
}

// MARK: - View

struct UninstallView: View {
    @Bindable var model: UninstallModel
    @State private var dropTargeted = false

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                TextField("Search apps", text: $model.search).textFieldStyle(.roundedBorder).padding(10)
                List(model.filtered, selection: Binding(get: { model.selected?.id }, set: { id in
                    if let id, let e = model.apps.first(where: { $0.id == id }) { model.select(e) }
                })) { app in
                    HStack(spacing: 10) {
                        Image(nsImage: app.icon).resizable().frame(width: 28, height: 28).accessibilityHidden(true)
                        Text(app.name).lineLimit(1)
                        Spacer()
                        Text(app.size.map(Bytes.string) ?? "…").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .tag(app.id)
                    .accessibilityLabel(Text("\(app.name), \(app.size.map(Bytes.string) ?? "")"))
                }
                .listStyle(.inset)
            }
            .frame(minWidth: 260, idealWidth: 300, maxHeight: .infinity)

            detail.frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 820, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)
        .overlay {
            if dropTargeted {
                ZStack {
                    Color.black.opacity(0.35)
                    Text("Drop the app here").font(.title2.weight(.semibold)).foregroundStyle(.white)
                }
                .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            for p in providers {
                p.loadItem(forTypeIdentifier: "public.file-url") { item, _ in
                    guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil), url.pathExtension == "app" else { return }
                    Task { @MainActor in model.pick(url) }
                }
            }
            return true
        }
        .onAppear { model.load() }
    }

    @ViewBuilder
    private var detail: some View {
        if let app = model.selected {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Image(nsImage: app.icon).resizable().frame(width: 64, height: 64).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.name).font(.title.weight(.bold))
                        Text(app.bundleID ?? app.path).font(.caption.monospaced()).foregroundStyle(.secondary)
                        Text("App itself: \(app.size.map(Bytes.string) ?? "…")").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                switch model.phase {
                case .working(let done, let total):
                    ProgressView(value: Double(done), total: Double(max(total, 1))) { Text("Removing \(app.name)…") }
                    Spacer()
                case .done(let moved, let size, let failed):
                    VStack(alignment: .leading, spacing: 8) {
                        Label("\(app.name) is gone", systemImage: "checkmark.circle.fill").font(.title2.weight(.semibold)).foregroundStyle(Tidy.green)
                        Text("\(moved) items moved to the Trash, \(Bytes.string(size)). Empty the Trash to free the space, or use What Tidy for Mac did to put it back.")
                        if failed > 0 { Text("\(failed) items couldn't be moved because macOS protects them.").foregroundStyle(.secondary) }
                        Button("Done") { model.reset() }.buttonStyle(.borderedProminent).tint(Tidy.green).controlSize(.large)
                    }
                    Spacer()
                case .failed(let msg):
                    Label(msg, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Tidy.orange)
                    Button("OK") { model.reset() }.controlSize(.large)
                    Spacer()
                default:
                    Text("Files this app left around your Mac").font(.headline)
                    if model.phase == .finding {
                        HStack { ProgressView().controlSize(.small); Text("Looking…").foregroundStyle(.secondary) }
                    } else if model.related.isEmpty {
                        Text("Nothing else found. Just the app itself will be removed.").foregroundStyle(.secondary)
                    }
                    List {
                        ForEach(model.related) { item in
                            HStack(spacing: 10) {
                                Toggle("", isOn: Binding(get: { item.selected }, set: { _ in model.toggle(item.id) }))
                                    .toggleStyle(.checkbox).labelsHidden().disabled(item.isProtected)
                                    .accessibilityLabel(Text("Remove \(item.name)"))
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 6) {
                                        Text(item.name).lineLimit(1)
                                        if let p = item.protectedBy {
                                            Label("Protected: \(p)", systemImage: "shield.fill").font(.caption).foregroundStyle(Tidy.blue)
                                        }
                                    }
                                    Text(item.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(Bytes.string(item.size)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listStyle(.inset)
                    HStack {
                        Text("Total: \(Bytes.string(model.totalToRemove))").font(.callout.weight(.semibold))
                        Spacer()
                        Button {
                            model.uninstall()
                        } label: {
                            Label("Uninstall \(app.name)", systemImage: "trash").padding(.horizontal, 8).padding(.vertical, 2)
                        }
                        .buttonStyle(.borderedProminent).tint(Tidy.red).controlSize(.large)
                        .disabled(model.phase == .finding)
                        .accessibilityHint(Text("Quits the app if it's open, then moves it and its files to the Trash"))
                    }
                    Text("Everything goes to the Trash, and a receipt is saved under What Tidy for Mac did.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(20)
        } else {
            ContentUnavailableView("Pick an app", systemImage: "trash.slash",
                                   description: Text("Choose an app on the left, or drag one in from Finder. Tidy for Mac finds everything it left behind and removes it all together."))
        }
    }
}
