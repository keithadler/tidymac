//  Speed tab UI, third batch: safety check-up, device batteries, default apps, quick fixes.

import SwiftUI

// MARK: - Safety check-up

struct SafetyCard: View {
    @Bindable var model: SpeedModel

    var body: some View {
        SpeedCard(title: String(localized: "Safety check-up"), icon: "lock.shield.fill", color: Tidy.green,
                  subtitle: String(localized: "Five switches that protect a family Mac. They're all free and none of them slow anything down.")) {
            if let checks = model.safety {
                ForEach(checks) { c in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: c.ok == true ? "checkmark.circle.fill" : (c.ok == false ? "exclamationmark.triangle.fill" : "questionmark.circle"))
                            .foregroundStyle(c.ok == true ? Tidy.green : (c.ok == false ? Tidy.orange : .secondary))
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.name).fontWeight(.medium)
                            Text(c.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if c.ok == false, let pane = c.fixPane {
                            Button("Fix") { SystemInfo.openSettings(pane) }.controlSize(.small)
                        }
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
            } else {
                HStack { ProgressView().controlSize(.small); Text("Checking…").foregroundStyle(.secondary) }
            }
        }
    }
}

// MARK: - Device batteries

struct DeviceBatteryCard: View {
    @Bindable var model: SpeedModel

    var body: some View {
        if let devs = model.deviceBatteries, !devs.isEmpty {
            SpeedCard(title: String(localized: "Your devices' batteries"), icon: "airpods", color: Tidy.blue,
                      subtitle: String(localized: "Headphones, mice, keyboards and trackpads connected over Bluetooth.")) {
                ForEach(devs) { d in
                    HStack(spacing: 10) {
                        Image(systemName: icon(for: d.kind)).foregroundStyle((d.lowest ?? 100) < 20 ? Tidy.red : Tidy.blue).frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(d.name).fontWeight(.medium)
                            if !d.kind.isEmpty { Text(d.kind).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        HStack(spacing: 10) {
                            ForEach(d.levels, id: \.0) { label, pct in
                                HStack(spacing: 4) {
                                    if !label.isEmpty { Text(label).font(.caption).foregroundStyle(.secondary) }
                                    Text("\(pct)%").font(.callout.monospacedDigit()).foregroundStyle(pct < 20 ? Tidy.red : .primary)
                                }
                            }
                        }
                        if (d.lowest ?? 100) < 20 { Text("charge soon").font(.caption.weight(.semibold)).foregroundStyle(Tidy.red) }
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
                Text("Devices only report while connected. Charge anything under 20% before it dies mid-use.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func icon(for kind: String) -> String {
        let k = kind.lowercased()
        if k.contains("headphone") || k.contains("airpod") { return "airpods" }
        if k.contains("mouse") { return "computermouse" }
        if k.contains("keyboard") { return "keyboard" }
        if k.contains("trackpad") { return "rectangle.and.hand.point.up.left" }
        if k.contains("speaker") { return "hifispeaker" }
        return "dot.radiowaves.left.and.right"
    }
}

// MARK: - Default apps

struct DefaultAppsCard: View {
    @Bindable var model: SpeedModel

    var body: some View {
        SpeedCard(title: String(localized: "Which app opens what"), icon: "arrow.up.forward.app", color: Tidy.purple,
                  subtitle: String(localized: "When a link opens in the wrong browser or a PDF opens somewhere strange, this is the switch.")) {
            ForEach(model.defaultApps) { slot in
                HStack(spacing: 10) {
                    Text(slot.name).frame(width: 190, alignment: .leading)
                    if let cur = slot.current {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: cur)).resizable().frame(width: 20, height: 20)
                    }
                    Menu {
                        ForEach(slot.candidates, id: \.self) { p in
                            Button(URL(fileURLWithPath: p).deletingPathExtension().lastPathComponent) { model.setDefault(slot, p) }
                        }
                    } label: {
                        Text(slot.current.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? String(localized: "Nothing set"))
                    }
                    .frame(maxWidth: 240)
                    .accessibilityLabel(Text("App for \(slot.name)"))
                    Spacer()
                }
                .padding(.vertical, 2)
            }
            Text("macOS asks you to confirm when the web or email app changes. That's normal.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Quick fixes

struct QuickFixCard: View {
    @Bindable var model: SpeedModel

    var body: some View {
        SpeedCard(title: String(localized: "Quick fixes"), icon: "wrench.and.screwdriver.fill", color: Tidy.orange,
                  subtitle: String(localized: "The things a helpful friend would try first. Each one is safe and takes a second; open windows may blink.")) {
            ForEach(SystemInfo3.availableFixes) { f in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(f.name).fontWeight(.medium)
                        Text(f.when).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button(f.key == "spotlight" ? "Copy command" : "Do it") { model.runFix(f) }.controlSize(.small)
                        .disabled(model.fixRunning == f.key)
                        .accessibilityLabel(Text(f.name))
                }
                .padding(.vertical, 3)
                Divider()
            }
        }
    }
}
