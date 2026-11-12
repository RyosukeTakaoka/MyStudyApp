import Foundation
import Observation

// メイン画面に出すデータを持つ場所(React でいう状態管理のストア)。
// 画面はこの中の値を表示するだけで、読み込みや保存の手順はここに集めています。
@MainActor
@Observable
final class DayStore {
    /// 表示している日付("2026-11-13" の形)
    private(set) var selectedDate: String
    /// 今日の日付(日付が変わったら refreshToday() で更新する)
    private(set) var today: String
    /// その日の予定とタスク(表示順にならべ済み)
    private(set) var items: [PlanItem] = []
    /// その日の目標・ふりかえり(まだ行が無い日は nil)
    private(set) var day: DayInfo?
    /// 通信中か
    private(set) var isLoading = false
    /// 表示中の日の読み込みが一度でも終わったか(「読み込み中」表示に使う)
    private(set) var hasLoaded = false
    /// 画面に出すエラーの文(無ければ nil)
    var errorMessage: String?
    /// ふりかえりの入力欄の中身(保存前の下書き)
    var reflectionDraft = ""

    private let userId: UUID
    private let api = RemoteAPI()

    init(userId: UUID) {
        self.userId = userId
        let today = DayKey.today()
        self.today = today
        self.selectedDate = today
    }

    // MARK: - 画面から使う値

    var blocks: [PlanItem] { items.filter(\.isBlock) }
    var tasks: [PlanItem] { items.filter { !$0.isBlock } }
    var doneCount: Int { items.filter(\.done).count }
    var totalCount: Int { items.count }
    var isToday: Bool { selectedDate == today }

    /// 保存済みのふりかえり(無ければ空文字)
    var savedReflection: String { day?.reflection ?? "" }
    /// 下書きが、保存済みの内容から変わっているか
    var isReflectionDirty: Bool { reflectionDraft != savedReflection }

    // MARK: - 日付の切り替え

    func goToPreviousDay() async { await select(DayKey.adding(-1, to: selectedDate)) }
    func goToNextDay() async { await select(DayKey.adding(1, to: selectedDate)) }
    func goToToday() async { await select(today) }

    /// 表示する日付を変える
    func select(_ date: String) async {
        guard date != selectedDate else { return }
        // 書きかけのふりかえりが消えないように、先に保存する
        await saveReflectionIfNeeded()

        selectedDate = date
        items = []
        day = nil
        reflectionDraft = ""
        hasLoaded = false
        await load()
    }

    /// アプリが前面に戻ったときに呼ぶ。日付が変わっていたら「今日」を更新する
    func refreshToday() async {
        let newToday = DayKey.today()
        guard newToday != today else { return }
        let wasShowingToday = isToday
        today = newToday
        // 「今日」を見ていた場合は、新しい今日に移る(昨日の画面のまま残らないように)
        if wasShowingToday {
            await select(newToday)
        }
    }

    // MARK: - 読み込み

    /// サーバーから、表示中の日の予定を読み込む
    func load() async {
        isLoading = true
        defer { isLoading = false }

        let date = selectedDate
        do {
            // 「async let」で2つの通信を同時に進める
            async let fetchedItems = api.fetchItems(from: date, to: date)
            async let fetchedDays = api.fetchDays(from: date, to: date)
            let (newItems, newDays) = try await (fetchedItems, fetchedDays)

            // 通信を待っているあいだに別の日へ移っていたら、この結果は捨てる
            guard date == selectedDate else { return }

            let wasDirty = isReflectionDirty
            items = PlanItem.sortedForDisplay(newItems)
            day = newDays.first
            // 書きかけでなければ、入力欄をサーバーの内容に合わせる
            if !wasDirty { reflectionDraft = savedReflection }
            hasLoaded = true
            errorMessage = nil
        } catch {
            guard date == selectedDate else { return }
            hasLoaded = true
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

    // MARK: - ふりかえり

    /// ふりかえりを保存する
    func saveReflection() async {
        let date = selectedDate
        let text = reflectionDraft
        do {
            try await api.saveReflection(userId: userId, date: date, reflection: text)
            // 保存を待っているあいだに別の日へ移っていなければ、画面の状態も更新する
            guard date == selectedDate else { return }
            if day == nil {
                day = DayInfo(date: date, goal: nil, reflection: text)
            } else {
                day?.reflection = text
            }
            errorMessage = nil
        } catch {
            errorMessage = "ふりかえりの保存に失敗しました。\n\(error.localizedDescription)"
        }
    }

    /// 書きかけがあるときだけ保存する(日付を変える前や、アプリを閉じるときに呼ぶ)
    func saveReflectionIfNeeded() async {
        if isReflectionDirty {
            await saveReflection()
        }
    }
}
