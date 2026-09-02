//  "What Tidy for Mac did": the receipts window. One section per session, a Put Back button per
//  record, and a Put Everything Back button per session.

import SwiftUI

/// "What Tidy for Mac did": every session, every item, and a Put Back button for each.
struct HistoryView: View {
    @State private var history = History.shared
    @State private var message: String?
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("What Tidy for Mac did").font(.title.weight(.bold))
                    Text("Everything Tidy for Mac has moved to the Trash. Anything still in the Trash can be put back exactly where it was.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)
            Divider()
            if history.sessions.isEmpty {
                ContentUnavailableView("Nothing yet", systemImage: "clock.arrow.circlepath",
                                       description: Text("Receipts appear here after your first tidy."))
            } else {
                List {
                    ForEach(history.sessions) { s in
                        SessionSection(session: s, busy: $busy, message: $message)
                    }
                }
                .listStyle(.inset)
            }
            if let message {
                Divider()
                HStack {
                    Image(systemName: "info.circle").foregroundStyle(Tidy.blue)
                    Text(message).font(.callout)
                    Spacer()
                    Button("OK") { self.message = nil }.controlSize(.small)
                }
                .padding(.horizontal, 20).padding(.vertical, 10).background(.bar)
            }
        }
        .frame(minWidth: 640, minHeight: 480)
    }
}

struct SessionSection: View {
    let session: TidySession
    @Binding var busy: Bool
    @Binding var message: String?
    @State private var expanded = false

    private var title: String {
        if let l = session.label { return l }
        return session.automatic ? String(localized: "Quiet tidy") : String(localized: "Tidy Up")
    }

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $expanded) {
                ForEach(session.records) { r in
                    HStack(spacing: 10) {
                        Image(systemName: r.restored ? "arrow.uturn.backward.circle.fill" : (r.moved ? "trash" : "xmark.circle"))
                            .foregroundStyle(r.restored ? Tidy.green : (r.moved ? .secondary : Tidy.red))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.name).lineLimit(1)
                            Text(r.originalPath).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Text(Bytes.string(r.size)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        if r.restored {
                            Text("Put back").font(.caption.weight(.semibold)).foregroundStyle(Tidy.green)
                        } else if r.moved {
                            Button("Put back") { restore(r) }.controlSize(.small).disabled(busy)
                                .accessibilityLabel(Text("Put back \(r.name)"))
                        } else {
                            Text("Not moved").font(.caption).foregroundStyle(Tidy.red)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: session.automatic ? "moon.zzz.fill" : "sparkles")
                        .foregroundStyle(session.automatic ? Tidy.purple : Tidy.green)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(title) · \(session.date.formatted(date: .abbreviated, time: .shortened))").fontWeight(.semibold)
                        Text("\(session.movedCount) items · \(Bytes.string(session.totalSize))\(session.failedCount > 0 ? " · \(session.failedCount) couldn't be moved" : "")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if session.restorableCount > 0 {
                        Button("Put everything back") { restoreAll() }.controlSize(.small).disabled(busy)
                    }
                }
            }
        }
    }

    private func restore(_ r: TidyRecord) {
        busy = true
        Task {
            let outcome = await History.shared.restore(r, in: session)
            message = describe(outcome, r.name)
            busy = false
        }
    }

    private func restoreAll() {
        busy = true
        Task {
            let (ok, gone, failed) = await History.shared.restoreAll(in: session)
            var parts: [String] = []
            if ok > 0 { parts.append(String(localized: "\(ok) put back")) }
            if gone > 0 { parts.append(String(localized: "\(gone) already gone from the Trash")) }
            if failed > 0 { parts.append(String(localized: "\(failed) couldn't be put back")) }
            message = parts.joined(separator: " · ")
            busy = false
        }
    }

    private func describe(_ o: RestoreOutcome, _ name: String) -> String {
        switch o {
        case .restored:      return String(localized: "\(name) is back where it was.")
        case .gone:          return String(localized: "\(name) isn't in the Trash any more. The Trash was emptied, so it can't be put back.")
        case .alreadyExists: return String(localized: "Something already exists where \(name) used to be, so it was left in the Trash.")
        case .failed(let e): return String(localized: "Couldn't put back \(name): \(e)")
        }
    }
}
