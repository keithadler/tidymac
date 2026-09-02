//  The main window's content: a segmented Tidy | Speed switch in the toolbar and the
//  matching view below it. The selected tab is remembered in UserDefaults ("mainTab").

import SwiftUI

/// The main window: Tidy (cleanup cards) and Speed (health and performance) side by side.
struct MainView: View {
    @Bindable var cleanup: CleanupModel
    @Bindable var speed: SpeedModel
    @Bindable var money: MoneyModel
    @AppStorage("mainTab") private var tab = 0
    @State private var reporting = false

    var body: some View {
        Group {
            switch tab {
            case 1: SpeedView(model: speed)
            case 2: MoneyView(model: money)
            default: CleanupView(model: cleanup)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Section", selection: $tab) {
                    Label("Tidy", systemImage: "sparkles").tag(0)
                    Label("Speed", systemImage: "gauge.with.dots.needle.67percent").tag(1)
                    Label("Money", systemImage: "dollarsign.circle").tag(2)
                }
                .pickerStyle(.segmented)
                .labelStyle(.titleAndIcon)
                .accessibilityLabel(Text("Section: Tidy, Speed, or Money"))
            }
            ToolbarItem(placement: .navigation) {
                Button { saveReport() } label: { Label("Save checkup report", systemImage: reporting ? "hourglass" : "doc.text") }
                    .disabled(reporting)
                    .help("One page with the health verdict, what a tidy would free, and the money findings. Good for handing to whoever helps with the Mac.")
            }
        }
    }

    private func saveReport() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Tidy checkup \(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")).html"
        panel.allowedContentTypes = [.html]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        reporting = true
        Task {
            let data = Report.gather()
            do { try Report.write(data, to: url, html: true); NSWorkspace.shared.open(url) } catch { NSSound.beep() }
            reporting = false
        }
    }
}
