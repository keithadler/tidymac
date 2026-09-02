//  Announcement images (docs/promo). Rendered by `tidymac screenshots <dir>` alongside the README
//  screenshots, from the same sample data, at 1600×900 (X / Twitter's 16:9) with a 2× backing store.

import SwiftUI
import AppKit

enum Promo {
    static let size = CGSize(width: 1600, height: 900)

    static var appIcon: NSImage {
        if let u = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let i = NSImage(contentsOf: u) { return i }
        if let i = NSImage(contentsOfFile: "AppIcon.icns") { return i }
        return NSApp.applicationIconImage
    }

    // Concrete types on purpose: opaque `some View` helpers shared across cards tripped a SwiftUI
    // metadata crash when rendered off-screen.
    static var gradient: LinearGradient {
        LinearGradient(colors: [Color(red: 0.06, green: 0.36, blue: 0.30), Color(red: 0.10, green: 0.55, blue: 0.42), Color(red: 0.16, green: 0.66, blue: 0.42)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    struct Shot: View {
        let image: NSImage?
        let width: CGFloat
        var body: some View {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    .frame(width: width)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                    .shadow(color: .black.opacity(0.35), radius: 30, y: 16)
            } else {
                Color.clear.frame(width: width, height: 10)
            }
        }
    }

    // 1. Hero
    struct Hero: View {
        let tidy: NSImage?
        var body: some View {
            ZStack {
                gradient
                HStack(spacing: 40) {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack(spacing: 18) {
                            Image(nsImage: appIcon).resizable().frame(width: 110, height: 110)
                            Text("Tidy for Mac").font(.system(size: 64, weight: .bold)).foregroundStyle(.white)
                        }
                        Text("A friendly, safe cleanup and speed-up\nfor the whole family.")
                            .font(.system(size: 34, weight: .medium)).foregroundStyle(.white.opacity(0.95)).lineSpacing(4)
                        VStack(alignment: .leading, spacing: 12) {
                            bullet("Everything goes to the Trash first, never deleted")
                            bullet("Every action has a receipt. Put anything back")
                            bullet("Never asks for a password")
                            bullet("Free and open source · MIT")
                        }
                        .padding(.top, 6)
                    }
                    .frame(width: 720, alignment: .leading)
                    Shot(image: tidy, width: 700)
                }
                .padding(.horizontal, 70)
            }
        }
        func bullet(_ t: String) -> some View {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 26)).foregroundStyle(.white)
                Text(t).font(.system(size: 26)).foregroundStyle(.white)
            }
        }
    }

    // 2. Claude
    struct ClaudeCard: View {
        let model: CleanupModel
        var body: some View {
            ZStack {
                LinearGradient(colors: [Color(red: 0.36, green: 0.20, blue: 0.10), Color(red: 0.72, green: 0.40, blue: 0.22), Color(red: 0.85, green: 0.47, blue: 0.28)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                HStack(spacing: 44) {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("It tidies up\nafter Claude, too.").font(.system(size: 58, weight: .bold)).foregroundStyle(.white).lineSpacing(2)
                        Text("Rendering caches, old Claude Code versions, the 10 GB sandbox image, month-old transcripts. Found, explained in plain English, and only the safe parts pre-checked.")
                            .font(.system(size: 25)).foregroundStyle(.white.opacity(0.95)).lineSpacing(4)
                        Text("Also: Chrome, Xcode, npm, pip, Homebrew, iPhone backups, duplicates, leftovers from removed apps…")
                            .font(.system(size: 21)).foregroundStyle(.white.opacity(0.8)).lineSpacing(3)
                    }
                    .frame(width: 640, alignment: .leading)
                    if let cat = model.categories.first {
                        CategoryCard(model: model, category: cat)
                            .frame(width: 720)
                            .background(RoundedRectangle(cornerRadius: 18).fill(Color(nsColor: .windowBackgroundColor)))
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .shadow(color: .black.opacity(0.35), radius: 30, y: 16)
                            .environment(\.colorScheme, .light)
                    }
                }
                .padding(.horizontal, 70)
            }
        }
    }

    // 3. Three tabs
    struct Tabs: View {
        let tidy: NSImage?, speed: NSImage?, money: NSImage?
        var body: some View {
            ZStack {
                gradient
                VStack(spacing: 26) {
                    Text("Three tabs. No jargon. No upsell.").font(.system(size: 52, weight: .bold)).foregroundStyle(.white)
                    HStack(alignment: .top, spacing: 30) {
                        column("Tidy", "What's safe to clear, and why", tidy)
                        column("Speed", "Health verdict, startup, sleep, Wi-Fi, 21 cards", speed)
                        column("Money", "Subscriptions you don't use, and \"don't replace this Mac yet\"", money)
                    }
                }
                .padding(.horizontal, 60).padding(.top, 40)
            }
        }
        func column(_ title: String, _ sub: String, _ img: NSImage?) -> some View {
            VStack(spacing: 10) {
                Text(title).font(.system(size: 30, weight: .semibold)).foregroundStyle(.white)
                Text(sub).font(.system(size: 18)).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center).frame(height: 48, alignment: .top)
                if let img {
                    // Fit the full width and show the top of the window; cropping the sides would lose the checkboxes.
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).frame(width: 470)
                        .frame(width: 470, height: 560, alignment: .top).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 16)).shadow(color: .black.opacity(0.35), radius: 24, y: 12)
                }
            }
        }
    }

    // 4. Command line
    struct CLIcard: View {
        var body: some View {
            ZStack {
                LinearGradient(colors: [Color(red: 0.08, green: 0.09, blue: 0.13), Color(red: 0.13, green: 0.16, blue: 0.24)], startPoint: .top, endPoint: .bottom)
                HStack(spacing: 50) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Also a real\ncommand line.").font(.system(size: 58, weight: .bold)).foregroundStyle(.white)
                        Text("Same scanners as the app, so they can never disagree. --json everywhere, exit codes for monitoring, a man page, receipts you can undo.")
                            .font(.system(size: 24)).foregroundStyle(.white.opacity(0.9)).lineSpacing(4)
                        Text("Built with Swift Package Manager. No Xcode. Universal binary.").font(.system(size: 20)).foregroundStyle(.white.opacity(0.7))
                    }
                    .frame(width: 600, alignment: .leading)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 8) {
                            ForEach([Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18), Color(red: 0.16, green: 0.79, blue: 0.26)], id: \.self) { Circle().fill($0).frame(width: 14, height: 14) }
                            Spacer()
                        }
                        .padding(16)
                        Text("""
                        $ tidymac scan
                        == App caches  [Always safe]  2.28 GB in 4 items, 4 pre-checked
                           [x] 1.24 GB    Safari  — Cache · used today
                           [x] 612 MB     Photo Editor  — Cache · last used 2 months ago
                        == Exact duplicate files  [Keeps one copy]  1.85 GB
                           [x] 1.85 GB    Holiday 2025.mov  — 2 identical copies

                        $ tidymac up --safe --dry-run
                        Would move 10 items (4.77 GB) to the Trash. Nothing was changed.

                        $ tidymac speed --json | jq .verdict
                        "green"

                        $ tidymac restore last
                        Put back 10 items.
                        """)
                        .font(.system(size: 19, design: .monospaced)).foregroundStyle(Color(red: 0.85, green: 0.93, blue: 0.85))
                        .padding(.horizontal, 22).padding(.bottom, 22)
                    }
                    .frame(width: 800, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(red: 0.05, green: 0.06, blue: 0.09)))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.15)))
                    .shadow(color: .black.opacity(0.5), radius: 30, y: 16)
                }
                .padding(.horizontal, 70)
            }
        }
    }

    /// Renders all four cards into `dir/promo`.
    @MainActor
    static func render(into dir: URL, shots: URL) {
        let out = dir.appendingPathComponent("promo")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        func img(_ n: String) -> NSImage? { NSImage(contentsOf: shots.appendingPathComponent("\(n).png")) }
        let claude = CleanupModel()
        claude.categories = [CleanCategory(kind: .claude, items: [
            CleanItem(id: "c1", paths: ["/x"], name: "Claude sandbox image", detail: "used for isolated sessions · used 15 days ago", size: 9_970_000_000, selected: false),
            CleanItem(id: "c2", paths: ["/x"], name: "Claude rendering cache · Cache", detail: "used today", size: 1_300_000_000, selected: true),
            CleanItem(id: "c3", paths: ["/x"], name: "Claude rendering cache · Code Cache", detail: "used today", size: 350_000_000, selected: true),
            CleanItem(id: "c4", paths: ["/x"], name: "Old Claude Code version 2.1.255", detail: "superseded by 2.1.258", size: 200_000_000, selected: true),
            CleanItem(id: "c5", paths: ["/x"], name: "Claude Code conversations older than a month", detail: "8 transcripts", size: 4_400_000, selected: false),
        ], expanded: true)]
        claude.phase = .ready
        let cards: [(String, AnyView)] = [
            ("1-hero", AnyView(Hero(tidy: img("tidy")))),
            ("2-claude", AnyView(ClaudeCard(model: claude))),
            ("3-tabs", AnyView(Tabs(tidy: img("tidy"), speed: img("speed"), money: img("money")))),
            ("4-cli", AnyView(CLIcard())),
        ]
        for (name, view) in cards {
            if let png = Screenshots.snapshot(view, size: size, title: "", chrome: false) {
                try? png.write(to: out.appendingPathComponent("\(name).png"))
                print("wrote promo/\(name).png")
            }
        }
    }
}
