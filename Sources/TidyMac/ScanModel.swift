//  Observable state for the Disk Map window: runs DiskUtil.scan() off the main thread and
//  keeps the current selection.

import Foundation
import Observation

@MainActor
@Observable
final class ScanModel {
    var scan: DiskScan?
    var error: String?
    var loading = false
    var selection: String?

    func refresh() {
        guard !loading else { return }
        loading = true
        error = nil
        Task {
            do {
                let s = try await Task.detached(priority: .userInitiated) { try DiskUtil.scan() }.value
                scan = s
                if selection == nil || s.find(selection!) == nil { selection = s.boot.bootDevice }
            } catch {
                self.error = String(describing: error)
            }
            loading = false
        }
    }

    var selectedNode: DiskNode? {
        guard let scan, let selection else { return nil }
        return scan.find(selection)
    }
}
