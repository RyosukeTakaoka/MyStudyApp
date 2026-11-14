import Foundation

/// アプリで予定を「足した・直した・消した」記録(まだサーバーに送っていないもの)
enum ItemEdit: Codable, Equatable, Sendable {
    /// 足した・直した(行の中身をまるごと送る)
    case upsert(PlanItem)
    /// 消した
    case delete(UUID)

    var itemId: UUID {
        switch self {
        case .upsert(let item): return item.id
        case .delete(let id): return id
        }
    }
}

/// まだ送っていない編集をためておく場所(端末のファイル)。
/// 同じ予定への編集は、いちばん新しいものだけを残す
@MainActor
final class ItemEditQueue {
    private(set) var pending: [ItemEdit] = []
    private let fileURL: URL?

    init(fileURL: URL? = ItemEditQueue.defaultFileURL) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([ItemEdit].self, from: data) {
            pending = saved
        }
    }

    nonisolated static var defaultFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("item-edits.json")
    }

    nonisolated static func clearSaved() {
        if let url = defaultFileURL { try? FileManager.default.removeItem(at: url) }
    }

    /// 送っていない編集がある予定の id(同期で受け取ったデータに上書きさせないために使う)
    var pendingIds: Set<UUID> { Set(pending.map(\.itemId)) }

    func add(_ edit: ItemEdit) {
        pending.removeAll { $0.itemId == edit.itemId }
        pending.append(edit)
        save()
    }

    /// 送り終わったものを取りのぞく(送っているあいだに、さらに編集されたものは残す)
    func remove(_ sent: [ItemEdit]) {
        pending.removeAll { sent.contains($0) }
        save()
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(pending) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
