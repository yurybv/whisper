import AppKit
import Foundation

struct PasteboardItemSnapshot: Equatable, Sendable {
    let representations: [String: Data]
}

struct PasteboardSnapshot: Equatable, Sendable {
    let items: [PasteboardItemSnapshot]
}

@MainActor
protocol PasteboardClient: Sendable {
    func captureSnapshot() -> PasteboardSnapshot
    func writeText(_ text: String) -> Bool
    func restore(_ snapshot: PasteboardSnapshot)
}

@MainActor
protocol PasteboardRestoring: Sendable {
    func placeTextPreservingCurrentContents(_ text: String) -> PasteboardSnapshot?
    func restore(_ snapshot: PasteboardSnapshot)
}

@MainActor
struct PasteboardRestorer: PasteboardRestoring {
    private let client: any PasteboardClient

    init(client: any PasteboardClient = SystemPasteboardClient()) {
        self.client = client
    }

    func placeTextPreservingCurrentContents(_ text: String) -> PasteboardSnapshot? {
        let snapshot = client.captureSnapshot()
        guard client.writeText(text) else {
            client.restore(snapshot)
            return nil
        }
        return snapshot
    }

    func restore(_ snapshot: PasteboardSnapshot) {
        client.restore(snapshot)
    }
}

@MainActor
final class SystemPasteboardClient: PasteboardClient {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func captureSnapshot() -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            let representations = item.types.reduce(into: [String: Data]()) { values, type in
                if let data = item.data(forType: type) {
                    values[type.rawValue] = data
                }
            }
            return PasteboardItemSnapshot(representations: representations)
        }
        return PasteboardSnapshot(items: items)
    }

    func writeText(_ text: String) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    func restore(_ snapshot: PasteboardSnapshot) {
        pasteboard.clearContents()
        let items = snapshot.items.map { snapshotItem in
            let item = NSPasteboardItem()
            for (type, data) in snapshotItem.representations {
                item.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            return item
        }
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }
}
