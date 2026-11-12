import Foundation
import SwiftData

// 端末内の保存場所(キャッシュ)の本体。SwiftData を使って、iPhone の中のデータベースに保存します。
// ここに入れておくことで、電波がなくても前回の予定を表示でき、チェックも記録できます。
//
// 次の版でウィジェットを作るときのメモ:
//   ウィジェットは別のプログラムとして動くので、このデータを読むには
//   「App Group」という共有フォルダに保存場所を移す必要があります。

/// 端末に保存する予定1件(items テーブルの1行のコピー + 未送信フラグ)
@Model
final class CachedItem {
    var id: UUID
    var date: String
    var kind: String
    var startTime: String?
    var endTime: String?
    var title: String
    var subject: String
    var sortOrder: Int
    var source: String
    var done: Bool
    var doneAt: Date?
    var actualMinutes: Int?
    var note: String?
    /// まだサーバーに送っていないチェックの変更があるか
    var needsSync: Bool

    init(_ local: LocalItem) {
        let item = local.item
        self.id = item.id
        self.date = item.date
        self.kind = item.kind
        self.startTime = item.startTime
        self.endTime = item.endTime
        self.title = item.title
        self.subject = item.subject
        self.sortOrder = item.sortOrder
        self.source = item.source
        self.done = item.done
        self.doneAt = item.doneAt
        self.actualMinutes = item.actualMinutes
        self.note = item.note
        self.needsSync = local.needsSync
    }

    /// 中身を新しい値で上書きする
    func update(from local: LocalItem) {
        let item = local.item
        date = item.date
        kind = item.kind
        startTime = item.startTime
        endTime = item.endTime
        title = item.title
        subject = item.subject
        sortOrder = item.sortOrder
        source = item.source
        done = item.done
        doneAt = item.doneAt
        actualMinutes = item.actualMinutes
        note = item.note
        needsSync = local.needsSync
    }

    /// 画面やロジックで使う、ふつうの値(struct)に変換する
    var asLocal: LocalItem {
        LocalItem(
            item: PlanItem(
                id: id, date: date, kind: kind, startTime: startTime, endTime: endTime,
                title: title, subject: subject, sortOrder: sortOrder, source: source,
                done: done, doneAt: doneAt, actualMinutes: actualMinutes, note: note
            ),
            needsSync: needsSync
        )
    }
}

/// 端末に保存する1日の情報(days テーブルの1行のコピー + 未送信フラグ)
@Model
final class CachedDay {
    var date: String
    var goal: String?
    var reflection: String?
    /// まだサーバーに送っていないふりかえりがあるか
    var reflectionNeedsSync: Bool

    init(_ local: LocalDay) {
        self.date = local.info.date
        self.goal = local.info.goal
        self.reflection = local.info.reflection
        self.reflectionNeedsSync = local.reflectionNeedsSync
    }

    func update(from local: LocalDay) {
        goal = local.info.goal
        reflection = local.info.reflection
        reflectionNeedsSync = local.reflectionNeedsSync
    }

    var asLocal: LocalDay {
        LocalDay(
            info: DayInfo(date: date, goal: goal, reflection: reflection),
            reflectionNeedsSync: reflectionNeedsSync
        )
    }
}

@MainActor
final class SwiftDataStore: LocalStore {
    /// アプリ全体で1つだけ使う
    static let shared = SwiftDataStore()

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    private init() {
        container = Self.makeContainer()
    }

    /// 保存場所を開く。こわれていて開けないときは、作り直す
    /// (中身はサーバーのコピーなので、消えても次の同期で元にもどる)
    private static func makeContainer() -> ModelContainer {
        if let container = try? ModelContainer(for: CachedItem.self, CachedDay.self) {
            return container
        }
        // 1回目に失敗したら、保存ファイルを消してもう一度ためす
        let storePath = ModelConfiguration().url.path
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(atPath: storePath + suffix)
        }
        if let container = try? ModelContainer(for: CachedItem.self, CachedDay.self) {
            return container
        }
        // それでもだめなら、メモリの中だけで動かす(アプリを閉じると消えるが、動作はする)
        do {
            return try ModelContainer(
                for: CachedItem.self, CachedDay.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        } catch {
            fatalError("端末内の保存場所を作れませんでした: \(error)")
        }
    }

    // MARK: - 読む

    func items(on dates: [String]) -> [LocalItem] {
        // #Predicate は「どの行を取り出すか」の条件(SQL の where にあたる)
        let descriptor = FetchDescriptor<CachedItem>(
            predicate: #Predicate<CachedItem> { item in dates.contains(item.date) }
        )
        return fetch(descriptor).map(\.asLocal)
    }

    func item(id: UUID) -> LocalItem? {
        models(withIds: [id]).first?.asLocal
    }

    func days(on dates: [String]) -> [LocalDay] {
        models(onDates: dates).map(\.asLocal)
    }

    func pendingItems() -> [LocalItem] {
        let descriptor = FetchDescriptor<CachedItem>(
            predicate: #Predicate<CachedItem> { item in item.needsSync == true }
        )
        return fetch(descriptor).map(\.asLocal)
    }

    func pendingDays() -> [LocalDay] {
        let descriptor = FetchDescriptor<CachedDay>(
            predicate: #Predicate<CachedDay> { day in day.reflectionNeedsSync == true }
        )
        return fetch(descriptor).map(\.asLocal)
    }

    // MARK: - 書く

    func save(items: [LocalItem]) {
        guard !items.isEmpty else { return }
        // すでにある行を id で引けるようにしておく
        var existing: [UUID: CachedItem] = [:]
        for model in models(withIds: items.map(\.item.id)) where existing[model.id] == nil {
            existing[model.id] = model
        }
        for local in items {
            if let model = existing[local.item.id] {
                model.update(from: local)          // あれば上書き
            } else {
                let model = CachedItem(local)      // なければ追加
                context.insert(model)
                existing[local.item.id] = model
            }
        }
        saveContext()
    }

    func save(days: [LocalDay]) {
        guard !days.isEmpty else { return }
        var existing: [String: CachedDay] = [:]
        for model in models(onDates: days.map(\.info.date)) where existing[model.date] == nil {
            existing[model.date] = model
        }
        for local in days {
            if let model = existing[local.info.date] {
                model.update(from: local)
            } else {
                let model = CachedDay(local)
                context.insert(model)
                existing[local.info.date] = model
            }
        }
        saveContext()
    }

    func deleteItems(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        for model in models(withIds: ids) {
            context.delete(model)
        }
        saveContext()
    }

    func deleteDays(dates: [String]) {
        guard !dates.isEmpty else { return }
        for model in models(onDates: dates) {
            context.delete(model)
        }
        saveContext()
    }

    func deleteEverything() {
        for model in fetch(FetchDescriptor<CachedItem>()) {
            context.delete(model)
        }
        for model in fetch(FetchDescriptor<CachedDay>()) {
            context.delete(model)
        }
        saveContext()
    }

    // MARK: - 中で使う道具

    private func models(withIds ids: [UUID]) -> [CachedItem] {
        fetch(FetchDescriptor<CachedItem>(
            predicate: #Predicate<CachedItem> { item in ids.contains(item.id) }
        ))
    }

    private func models(onDates dates: [String]) -> [CachedDay] {
        fetch(FetchDescriptor<CachedDay>(
            predicate: #Predicate<CachedDay> { day in dates.contains(day.date) }
        ))
    }

    private func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> [T] {
        do {
            return try context.fetch(descriptor)
        } catch {
            print("端末内データの読み込みに失敗: \(error)")
            return []
        }
    }

    private func saveContext() {
        do {
            try context.save()
        } catch {
            print("端末内データの保存に失敗: \(error)")
        }
    }
}
