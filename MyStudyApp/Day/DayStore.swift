import Foundation
import Observation

// 「今日の画面」に出すデータを持つ場所(React でいう状態管理のストア)。
// 画面はこの中の値を表示するだけで、読み込みや保存の手順はここに集めています。
@MainActor
@Observable
final class DayStore {
    /// 表示している日付("2026-11-13" の形)
    private(set) var selectedDate: String = DayKey.today()
    /// その日の予定とタスク(表示順にならべ済み)
    private(set) var items: [PlanItem] = []
    /// その日の目標・ふりかえり(まだ行が無い日は nil)
    private(set) var day: DayInfo?
    /// 通信中か
    private(set) var isLoading = false
    /// 一度でも読み込みが終わったか(最初の「読み込み中」表示に使う)
    private(set) var hasLoaded = false
    /// 画面に出すエラーの文(無ければ nil)
    var errorMessage: String?

    private let api = RemoteAPI()

    // MARK: - 画面から使う値

    var blocks: [PlanItem] { items.filter(\.isBlock) }
    var tasks: [PlanItem] { items.filter { !$0.isBlock } }
    var doneCount: Int { items.filter(\.done).count }
    var totalCount: Int { items.count }

    // MARK: - 読み込み

    /// サーバーから、表示中の日の予定を読み込む
    func load() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        let date = selectedDate
        do {
            // 「async let」で2つの通信を同時に進める
            async let fetchedItems = api.fetchItems(from: date, to: date)
            async let fetchedDays = api.fetchDays(from: date, to: date)
            let (newItems, newDays) = try await (fetchedItems, fetchedDays)

            items = PlanItem.sortedForDisplay(newItems)
            day = newDays.first
            errorMessage = nil
        } catch {
            errorMessage = "読み込みに失敗しました。\n\(error.localizedDescription)"
        }
    }

    // MARK: - チェック

    /// 行がタップされたとき: チェックを付ける/外す
    func toggle(_ item: PlanItem) async {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let before = items[index]

        // 1. 先に画面を変える(通信を待たないので、タップした瞬間に ✓ が付く)
        var after = before
        after.done.toggle()
        after.doneAt = after.done ? Date() : nil
        items[index] = after

        // 2. サーバーに保存する
        do {
            try await api.setDone(id: after.id, done: after.done, doneAt: after.doneAt)
            errorMessage = nil
        } catch {
            // 3. 失敗したら元に戻す(ステップ6で「端末に保存して、あとで送る」方式に変えます)
            if let current = items.firstIndex(where: { $0.id == item.id }) {
                items[current] = before
            }
            errorMessage = "保存に失敗しました。\n\(error.localizedDescription)"
        }
    }
}
