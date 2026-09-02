//  The Tidy tab UI: disk gauge header (with the 10%-free guardrail), one CategoryCard per
//  CleanKind, an ItemRow per file with checkbox / thumbnail / shield / "why" popover, the footer
//  with the big Tidy Up button, and the confirmation sheets. Also defines the Tidy palette and
//  the ViewOptions keys for compact mode.

import SwiftUI
import UniformTypeIdentifiers
import QuickLookThumbnailing

/// Layout density and clutter options, shared by the View menu, the toolbar, and the cards.
enum ViewOptions {
    static let compact = "viewCompact"
    static let blurbs = "viewBlurbs"
    static let hideEmptySafe = "viewHideUnchecked"
}

struct CleanupView: View {
    @Bindable var model: CleanupModel
    @Environment(\.openWindow) private var openWindow
    @State private var dropTargeted = false
    @AppStorage(ViewOptions.compact) private var compact = false
    @AppStorage(ViewOptions.blurbs) private var showBlurbs = true

    var body: some View {
        VStack(spacing: 0) {
            Header(model: model)
            Divider()
            content
            Divider()
            Footer(model: model)
        }
        .frame(minWidth: 780, minHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if dropTargeted {
                ZStack {
                    Color.black.opacity(0.35)
                    VStack(spacing: 8) {
                        Image(systemName: "trash.slash.fill").font(.system(size: 44)).foregroundStyle(.white)
                        Text("Drop an app here to uninstall it completely").font(.title2.weight(.semibold)).foregroundStyle(.white)
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
            for p in providers {
                p.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil),
                          url.pathExtension == "app" else { return }
                    Task { @MainActor in
                        UninstallModel.shared.pick(url)
                        openWindow(id: "uninstall")
                    }
                }
            }
            return true
        }
        .toolbar {
            ToolbarItemGroup(placement: .secondaryAction) {
                Menu {
                    Toggle("Compact rows", isOn: $compact)
                    Toggle("Show explanations", isOn: $showBlurbs)
                    Divider()
                    Button("Expand all cards") { model.setAllExpanded(true) }
                    Button("Collapse all cards") { model.setAllExpanded(false) }
                } label: {
                    Label("View", systemImage: compact ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                }
                .help("Make the list denser or roomier")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { openWindow(id: "history") } label: { Label("What Tidy for Mac did", systemImage: "clock.arrow.circlepath") }
                    .help("See everything Tidy for Mac has moved, and put any of it back")
                Button { openWindow(id: "uninstall") } label: { Label("Uninstall an app", systemImage: "trash.slash") }
                    .help("Remove an app and everything it left behind")
                Button { openWindow(id: "spacemap") } label: { Label("Space map", systemImage: "square.grid.3x3.fill") }
                    .help("See what's taking up room, as a picture")
                Button { openWindow(id: "sorter") } label: { Label("Sort Desktop & Downloads", systemImage: "folder.badge.gearshape") }
                    .help("File loose files into folders by type, reversibly")
                SettingsLink { Label("Settings", systemImage: "gearshape") }
                    .help("Menu bar, weekly tidy, reminders, protected folders")
            }
        }
        .onAppear { if model.categories.isEmpty, model.phase == .idle { model.scan() } }
        .sheet(isPresented: $model.showConfirm) { CleanSheet(model: model) }
        .sheet(isPresented: $model.showTrashConfirm) { TrashSheet(model: model) }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            LazyVStack(spacing: compact ? 8 : 14) {
                ForEach(model.categories) { cat in
                    CategoryCard(model: model, category: cat, compact: compact, showBlurb: showBlurbs)
                }
                if model.isScanning {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        if case .scanning(let label) = model.phase { Text(label).foregroundStyle(.secondary) }
                    }
                    .padding(.vertical, 20)
                    .accessibilityElement(children: .combine)
                } else if model.categories.isEmpty, model.phase == .ready {
                    ContentUnavailableView("Sparkling clean!", systemImage: "sparkles",
                                           description: Text("There's nothing to tidy up right now."))
                        .padding(.top, 40)
                }
            }
            .padding(compact ? 12 : 20)
        }
    }
}

// MARK: - Header with disk gauge

struct Header: View {
    @Bindable var model: CleanupModel
    @AppStorage(ViewOptions.compact) private var compact = false

    private var headline: LocalizedStringKey {
        guard let s = model.space else { return "Let's tidy up." }
        if s.usedFraction < 0.7 { return "Plenty of room. A quick tidy keeps things zippy." }
        if s.usedFraction < 0.9 { return "Getting a little full. Let's make some space." }
        return "Almost full! Time to clear things out."
    }

    private var gaugeColor: Color {
        guard let s = model.space else { return .gray }
        if s.usedFraction < 0.7 { return Tidy.green }
        if s.usedFraction < 0.9 { return Tidy.orange }
        return Tidy.red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: compact ? 20 : 30, weight: .semibold))
                        .foregroundStyle(Tidy.green)
                        .accessibilityHidden(true)
                    if compact {
                        Text("Tidy for Mac").font(.title2.weight(.bold))
                        Text(headline).font(.callout).foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tidy for Mac").font(.largeTitle.weight(.bold))
                            Text(headline).font(.title3).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Button { model.scan() } label: { Label("Scan again", systemImage: "arrow.clockwise") }
                        .disabled(model.isScanning)
                        .keyboardShortcut("r", modifiers: .command)
                    if let last = model.lastTidy {
                        Text("Last tidy \(last.formatted(.relative(presentation: .named)))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if let s = model.space {
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.08))
                            RoundedRectangle(cornerRadius: 8).fill(gaugeColor.gradient)
                                .frame(width: max(8, geo.size.width * s.usedFraction))
                            // The 10%-free line macOS needs to stay responsive.
                            Rectangle().fill(Color.primary.opacity(0.5)).frame(width: 2)
                                .offset(x: geo.size.width * 0.9)
                                .help("Keep the bar left of this line: macOS needs about 10% free to run well")
                        }
                    }
                    .frame(height: compact ? 8 : 16)
                    HStack {
                        Text("\(Bytes.string(s.used)) used").foregroundStyle(.secondary)
                        if s.usedFraction > 0.9 {
                            Text("· past the 10% line, macOS will feel slow").foregroundStyle(Tidy.red).fontWeight(.semibold)
                        }
                        Spacer()
                        Text("\(Bytes.string(s.free)) free").fontWeight(.semibold).foregroundStyle(gaugeColor)
                        Text("of \(Bytes.string(s.total))").foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Disk space: \(Bytes.string(s.free)) free of \(Bytes.string(s.total)), \(Int(s.usedFraction * 100)) percent full"))
            }
        }
        .padding(.horizontal, compact ? 16 : 24).padding(.top, compact ? 10 : 20).padding(.bottom, compact ? 8 : 16)
    }
}

// MARK: - Category card

struct CategoryCard: View {
    @Bindable var model: CleanupModel
    let category: CleanCategory
    var compact = false
    var showBlurb = true

    private var kind: CleanKind { category.kind }
    private var color: Color { Tidy.color(for: kind) }
    private var safetyColor: Color {
        switch kind.safety { case .safe: return Tidy.green; case .copies: return Tidy.blue; case .mixed: return Tidy.teal; case .review: return Tidy.orange }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 10) {
            HStack(alignment: compact ? .center : .top, spacing: compact ? 10 : 14) {
                Toggle("", isOn: Binding(get: { category.allSelected }, set: { model.setAll(kind, $0) }))
                    .toggleStyle(.checkbox).labelsHidden().controlSize(compact ? .regular : .large)
                    .padding(.top, compact ? 0 : 4)
                    .disabled(category.selectable.isEmpty)
                    .accessibilityLabel(Text("Select everything in \(kind.title)"))
                ZStack {
                    Circle().fill(color.opacity(0.18)).frame(width: compact ? 28 : 44, height: compact ? 28 : 44)
                    Image(systemName: kind.icon).font(compact ? .body : .title2).foregroundStyle(color)
                }
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(kind.title).font(compact ? .headline : .title3.weight(.semibold))
                        Text(kind.safety.label)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(safetyColor.opacity(0.18), in: Capsule())
                            .foregroundStyle(safetyColor)
                    }
                    if showBlurb && !compact {
                        Text(kind.blurb).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .help(kind.blurb)
                Spacer(minLength: 12)
                if compact {
                    Text("\(category.items.count) items").font(.caption).foregroundStyle(.secondary)
                    if category.selectedCount > 0 && category.selectedCount < category.selectable.count {
                        Text("\(category.selectedCount) checked").font(.caption).foregroundStyle(color)
                    }
                    Text(Bytes.string(category.total)).font(.headline.monospacedDigit()).frame(minWidth: 80, alignment: .trailing)
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Bytes.string(category.total)).font(.title3.weight(.semibold).monospacedDigit())
                        Text("\(category.items.count) items").font(.caption).foregroundStyle(.secondary)
                        if category.selectedCount > 0 && category.selectedCount < category.selectable.count {
                            Text("\(category.selectedCount) checked").font(.caption).foregroundStyle(color)
                        }
                    }
                }
            }

            DisclosureGroup(isExpanded: Binding(get: { category.expanded }, set: { model.setExpanded(kind, $0) })) {
                VStack(spacing: 0) {
                    ForEach(category.items) { item in
                        ItemRow(item: item, kind: kind, color: color, compact: compact,
                                toggle: { model.toggle(kind, item.id) },
                                protect: { p in model.protect(p) })
                        if item.id != category.items.last?.id { Divider().padding(.leading, 28) }
                    }
                }
                .padding(.top, compact ? 2 : 6)
            } label: {
                Text(category.expanded ? "Hide items" : "Show items").font(compact ? .caption : .callout).foregroundStyle(color)
            }
            .padding(.leading, compact ? 26 : 30)
        }
        .padding(compact ? 10 : 16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.06)))
    }
}

struct ItemRow: View {
    let item: CleanItem
    let kind: CleanKind
    let color: Color
    var compact = false
    let toggle: () -> Void
    let protect: (String) -> Void
    @State private var showWhy = false

    private var showsThumbnail: Bool { kind == .duplicates || kind == .bigFiles || kind == .installers }

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { item.selected }, set: { _ in toggle() }))
                .toggleStyle(.checkbox).labelsHidden()
                .disabled(item.isProtected)
                .accessibilityLabel(Text(item.isProtected ? "\(item.name), protected" : "Select \(item.name)"))
            if showsThumbnail, !compact, let u = item.firstURL {
                Thumbnail(url: u).frame(width: 36, height: 36)
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(item.name).font(compact ? .callout : .body).lineLimit(1)
                    if let why = item.protectedBy {
                        Label("Protected: \(why)", systemImage: "shield.fill")
                            .font(.caption.weight(.semibold)).foregroundStyle(Tidy.blue)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Tidy.blue.opacity(0.12), in: Capsule())
                    }
                }
                if !compact { Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            .help(item.detail)
            Spacer()
            Text(Bytes.string(item.size)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            Button { showWhy.toggle() } label: { Image(systemName: "info.circle") }
                .buttonStyle(.borderless)
                .help("Why is this here?")
                .accessibilityLabel(Text("Why is \(item.name) here?"))
                .popover(isPresented: $showWhy, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Why is this here?").font(.headline)
                        Text(item.why).fixedSize(horizontal: false, vertical: true)
                        if let k = item.keeperPath {
                            Text("Kept: \(k)").font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        ForEach(item.paths.prefix(6), id: \.self) { p in
                            Text(p).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        if item.paths.count > 6 { Text("… and \(item.paths.count - 6) more").font(.caption).foregroundStyle(.tertiary) }
                    }
                    .padding(14).frame(width: 360)
                }
            Menu {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(item.paths.map { URL(fileURLWithPath: $0) })
                }
                if !item.isProtected, let p = item.paths.first {
                    Button("Never touch this") { protect(p) }
                }
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 24)
                .accessibilityLabel(Text("More actions for \(item.name)"))
        }
        .padding(.vertical, compact ? 2 : 6)
        .contentShape(Rectangle())
        .onTapGesture { toggle() }
        .opacity(item.isProtected ? 0.7 : 1)
    }
}

/// Quick Look thumbnail for a file, loaded lazily.
struct Thumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().aspectRatio(contentMode: .fit)
            }
        }
        .accessibilityHidden(true)
        .task(id: url) {
            let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 72, height: 72), scale: 2, representationTypes: .thumbnail)
            if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: req) {
                image = rep.nsImage
            }
        }
    }
}

// MARK: - Footer with the big button

struct Footer: View {
    @Bindable var model: CleanupModel
    @AppStorage(ViewOptions.compact) private var compact = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    if model.selectedCount > 0 {
                        Text("Ready to tidy: \(Bytes.string(model.selectedTotal))").font(.title3.weight(.semibold))
                        Text("\(model.selectedCount) items · \(Bytes.friendly(model.selectedTotal))").foregroundStyle(.secondary)
                    } else if model.isScanning {
                        Text("Looking around…").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                    } else {
                        Text("Nothing checked").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                        Text("Tick the boxes above to choose what to tidy.").foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let t = model.trash, !t.readable || t.count > 0 {
                    Button { model.showTrashConfirm = true } label: {
                        Label(t.readable ? "Empty Trash · \(Bytes.string(t.size))" : "Empty Trash…", systemImage: "trash")
                    }
                    .controlSize(.large)
                }
                Button { model.showConfirm = true } label: {
                    Label("Tidy Up", systemImage: "sparkles")
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent).tint(Tidy.green).controlSize(.large)
                .disabled(model.selectedCount == 0 || model.isScanning)
                .keyboardShortcut(.defaultAction)
                .accessibilityHint(Text("Moves the checked items to the Trash after asking you to confirm"))
            }
            if !compact {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill").foregroundStyle(Tidy.green).accessibilityHidden(true)
                    Text("Everything goes to the Trash first, so you can change your mind. Tidy for Mac never touches your photos, documents, or apps.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, compact ? 16 : 24).padding(.vertical, compact ? 8 : 14)
        .background(.bar)
    }
}

// MARK: - Sheets

struct CleanSheet: View {
    @Bindable var model: CleanupModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 18) {
            switch model.phase {
            case .cleaning(let done, let total):
                Image(systemName: "sparkles").font(.system(size: 40)).foregroundStyle(Tidy.green)
                Text("Tidying up…").font(.title2.weight(.semibold))
                ProgressView(value: Double(done), total: Double(max(total, 1))).frame(width: 300)
                Text("\(done) of \(total)").foregroundStyle(.secondary)

            case .finished(let moved, let size, let failed):
                Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(Tidy.green)
                Text("All done!").font(.title.weight(.bold))
                Text("\(moved) items went to the Trash, \(Bytes.string(size)) in all.").multilineTextAlignment(.center)
                if failed > 0 {
                    Text("\(failed) items couldn't be moved because macOS protects them. That's fine to leave as is.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                Text("The space isn't free yet. Empty the Trash when you're sure you don't need any of it. A receipt is saved under What Tidy for Mac did, so anything can be put back.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 400)
                HStack {
                    Button("See the receipt") { model.finishAndRescan(); openWindow(id: "history") }.controlSize(.large)
                    Button("Later") { model.finishAndRescan() }.controlSize(.large)
                    Button("Empty Trash now") { model.showConfirm = false; model.showTrashConfirm = true }
                        .buttonStyle(.borderedProminent).tint(Tidy.green).controlSize(.large)
                }

            default:
                Image(systemName: "trash").font(.system(size: 40)).foregroundStyle(Tidy.blue)
                Text("Move \(model.selectedCount) items to the Trash?").font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                Text("That's \(Bytes.string(model.selectedTotal)), \(Bytes.friendly(model.selectedTotal)).").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.categories.filter { $0.selectedCount > 0 }) { c in
                        HStack {
                            Circle().fill(Tidy.color(for: c.kind)).frame(width: 8, height: 8)
                            Text(c.kind.title)
                            Spacer()
                            Text("\(c.selectedCount) · \(Bytes.string(c.selectedTotal))").foregroundStyle(.secondary).monospacedDigit()
                        }
                        .font(.callout)
                    }
                }
                .padding(12).frame(width: 400)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                Text("Nothing is deleted. You can drag anything back out of the Trash, or use What Tidy for Mac did to put it back with one click.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 400)
                HStack {
                    Button("Cancel") { model.showConfirm = false }.controlSize(.large).keyboardShortcut(.cancelAction)
                    Button("Move to Trash") { model.clean() }
                        .buttonStyle(.borderedProminent).tint(Tidy.green).controlSize(.large).keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(30)
        .frame(minWidth: 460)
        .interactiveDismissDisabled({ if case .cleaning = model.phase { return true } else { return false } }())
    }
}

struct TrashSheet: View {
    @Bindable var model: CleanupModel

    var body: some View {
        VStack(spacing: 18) {
            switch model.phase {
            case .emptyingTrash:
                ProgressView("Emptying the Trash…").padding()

            case .trashEmptied(let freed):
                Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(Tidy.green)
                Text("Trash emptied").font(.title.weight(.bold))
                Text("You freed up \(Bytes.string(freed)), \(Bytes.friendly(freed)).").multilineTextAlignment(.center)
                if let s = model.space { Text("Your Mac now has \(Bytes.string(s.free)) free.").foregroundStyle(.secondary) }
                Button("Done") { model.finishAndRescan() }
                    .buttonStyle(.borderedProminent).tint(Tidy.green).controlSize(.large).keyboardShortcut(.defaultAction)

            case .trashFailed(let msg):
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 40)).foregroundStyle(Tidy.orange)
                Text("Couldn't empty the Trash").font(.title2.weight(.semibold))
                Text("macOS didn't let Tidy for Mac ask Finder to do it. You can empty it yourself: click the Trash in the Dock, then choose Empty.")
                    .multilineTextAlignment(.center).frame(maxWidth: 380).foregroundStyle(.secondary)
                Text(msg).font(.caption).foregroundStyle(.tertiary)
                Button("OK") { model.finishAndRescan() }.controlSize(.large).keyboardShortcut(.defaultAction)

            default:
                Image(systemName: "trash.fill").font(.system(size: 40)).foregroundStyle(Tidy.red)
                Text("Empty the Trash?").font(.title2.weight(.semibold))
                if let t = model.trash, t.readable {
                    Text("This permanently removes \(t.count) items, \(Bytes.string(t.size)). There's no getting them back after this, and receipts can no longer put things back.")
                        .multilineTextAlignment(.center).frame(maxWidth: 380).foregroundStyle(.secondary)
                } else {
                    Text("This permanently removes everything in the Trash. There's no getting it back after this.")
                        .multilineTextAlignment(.center).frame(maxWidth: 380).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Keep it") { model.showTrashConfirm = false; if case .finished = model.phase { model.finishAndRescan() } }
                        .controlSize(.large).keyboardShortcut(.cancelAction)
                    Button("Empty Trash") { model.emptyTrash() }
                        .buttonStyle(.borderedProminent).tint(Tidy.red).controlSize(.large)
                }
            }
        }
        .padding(30)
        .frame(minWidth: 420)
        .interactiveDismissDisabled(model.phase == .emptyingTrash)
    }
}

// MARK: - Palette

enum Tidy {
    static let green  = Color(red: 0.16, green: 0.66, blue: 0.42)
    static let blue   = Color(red: 0.20, green: 0.50, blue: 0.95)
    static let orange = Color(red: 0.95, green: 0.58, blue: 0.16)
    static let red    = Color(red: 0.88, green: 0.30, blue: 0.30)
    static let purple = Color(red: 0.58, green: 0.40, blue: 0.85)
    static let teal   = Color(red: 0.18, green: 0.62, blue: 0.68)
    static let brown  = Color(red: 0.60, green: 0.45, blue: 0.28)
    static let slate  = Color(red: 0.45, green: 0.50, blue: 0.58)
    static let pink   = Color(red: 0.86, green: 0.36, blue: 0.62)

    static func color(for kind: CleanKind) -> Color {
        switch kind {
        case .caches:     return blue
        case .logs:       return teal
        case .installers: return purple
        case .devCaches:  return slate
        case .claude:     return Color(red: 0.85, green: 0.47, blue: 0.28)
        case .duplicates: return pink
        case .leftovers:  return orange
        case .unusedApps: return Color(red: 0.50, green: 0.55, blue: 0.75)
        case .iosBackups: return brown
        case .bigFiles:   return red
        }
    }

    /// Palette for the space map, cycled by top-level folder.
    static let mapPalette: [Color] = [blue, green, orange, purple, teal, pink, brown, red, slate]
}
