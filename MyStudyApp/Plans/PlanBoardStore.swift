import Foundation
import Observation

/// 週次・期間の計画の読み書き(本物は RemoteAPI。テストではニセモノに差しかえる)
protocol PlanBoardAPI: Sendable {
    func fetchTermPlans(endingAfter from: String) async throws -> [TermPlan]
    func fetchWeeks(from: String, to: String) async throws -> [WeekPlan]
    func fetchWeekGoals(from: String, to: String) async throws -> [WeekGoal]
    func updateGoalBoxes(id: UUID, doneBoxes: [Int]) async throws
    func updateGoalLabels(id: UUID, labels: [String]) async throws
}

/// 端末に保存しておく中身(電波がなくても見られるように)
struct PlanBoardCache: Codable, Equatable {
    var terms: [TermPlan] = []
    var weeks: [WeekPlan] = []
    var goals: [WeekGoal] = []
    /// まだサーバーに送っていない「できた箱」(id → できた箱の番号)
    var pending: [UUID: [Int]] = [:]
    /// まだ送っていない「箱の名前」(前の版の保存データには無いので、無くても読めるように nil 可)
    var pendingLabels: [UUID: [String]]? = nil
}

// 「週・月」タブのデータを持つ場所。
// 考え方は今日の画面と同じで、画面は端末に保存した内容を表示し、裏でサーバーと同期します。
@MainActor
@Observable
final class PlanBoardStore {
    private(set) var terms: [TermPlan] = []
    private(set) var sections: [WeekSection] = []
    private(set) var isSyncing = false
    private(set) var hasLoadedOnce = false
    /// 同期できなかったときの文(うまくいっていれば nil)
    private(set) var problem: String?

    private var cache: PlanBoardCache
    private let api: PlanBoardAPI
    private let fileURL: URL?
    private let now: () -> Date
    private var syncAgain = false

    /// ウィジェット用のデータを書く場所(テストでは nil にして書かない)
    private let widgetDir: URL?

    init(api: PlanBoardAPI = RemoteAPI(), fileURL: URL? = PlanBoardStore.defaultFileURL,
         widgetDir: URL? = AppGroup.containerURL, now: @escaping () -> Date = Date.init) {
        self.api = api
        self.fileURL = fileURL
        self.widgetDir = widgetDir
        self.now = now
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode(PlanBoardCache.self, from: data) {
            cache = saved
            hasLoadedOnce = true
        } else {
            cache = PlanBoardCache()
        }
        rebuild()
    }

    /// 保存場所(アプリの書類フォルダの中)
    /// ウィジェット用のデータを作る(今週と来週)
    nonisolated static func widgetSnapshot(sections: [WeekSection], currentWeekStart: String) -> WeekWidgetSnapshot {
        let weeks = sections.filter { $0.week.weekStart >= currentWeekStart }.prefix(2).map { section in
            WeekWidgetSnapshot.Week(
                weekStart: section.week.weekStart,
                label: section.week.label,
                subtitle: section.week.subtitle,
                events: section.week.events,
                goals: section.groups.flatMap { group in
                    group.goals.map { goal in
                        WeekWidgetSnapshot.Goal(group: group.name, title: goal.title,
                                                target: goal.targetCount, doneBoxes: goal.doneBoxes)
                    }
                }
            )
        }
        return WeekWidgetSnapshot(weeks: Array(weeks))
    }

    nonisolated static var defaultFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("plan-board.json")
    }

    /// ログアウトしたときに、保存した内容を消す
    nonisolated static func clearSaved() {
        if let url = defaultFileURL { try? FileManager.default.removeItem(at: url) }
    }

    /// 今の週(画面を開いたとき、ここまでスクロールする)
    var currentWeekStart: String { DayKey.mondayOfWeek(DayKey.today(now: now())) }

    var pendingCount: Int { cache.pending.count + (cache.pendingLabels?.count ?? 0) }

    // MARK: - 操作

    /// 箱を押したとき: その箱だけが緑になる/戻る
    func tapBox(_ box: Int, of goal: WeekGoal) {
        guard let index = cache.goals.firstIndex(where: { $0.id == goal.id }) else { return }
        let next = WeekSection.doneBoxes(
            afterTapping: box,
            current: cache.goals[index].doneBoxes,
            target: cache.goals[index].targetCount
        )
        cache.goals[index].doneBoxes = next
        cache.pending[goal.id] = next
        save()
        rebuild()
        Task { await sync() }
    }

    /// 箱の名前(曜日など)を1つずつ付ける。label が nil なら名前を消す(自動の表示に戻す)
    func setBoxLabel(_ box: Int, of goal: WeekGoal, to label: String?) {
        guard let index = cache.goals.firstIndex(where: { $0.id == goal.id }) else { return }
        let next = WeekGoal.boxLabels(afterSetting: box, to: label,
                                      current: cache.goals[index].boxLabels, target: cache.goals[index].targetCount)
        cache.goals[index].boxLabels = next
        var labels = cache.pendingLabels ?? [:]
        labels[goal.id] = next
        cache.pendingLabels = labels
        save()
        rebuild()
        Task { await sync() }
    }

    /// サーバーと同期する(送る → 受け取る)。同時に2つ動かないようにする
    func sync() async {
        if isSyncing {
            syncAgain = true
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        repeat {
            syncAgain = false
            await syncOnce()
        } while syncAgain
    }

    private func syncOnce() async {
        // 1. 送る
        for (id, boxes) in cache.pending {
            do {
                try await api.updateGoalBoxes(id: id, doneBoxes: boxes)
                // 送っているあいだに押し直されていなければ、送信済みにする
                if cache.pending[id] == boxes { cache.pending[id] = nil }
            } catch {
                problem = Self.describe(error)
                save()
                return
            }
        }

        for (id, labels) in cache.pendingLabels ?? [:] {
            do {
                try await api.updateGoalLabels(id: id, labels: labels)
                if cache.pendingLabels?[id] == labels { cache.pendingLabels?[id] = nil }
            } catch {
                problem = Self.describe(error)
                save()
                return
            }
        }

        // 2. 受け取る(先週から8週間先まで)
        let today = DayKey.today(now: now())
        let from = DayKey.adding(-7, to: DayKey.mondayOfWeek(today))
        let to = DayKey.adding(56, to: from)
        do {
            async let terms = api.fetchTermPlans(endingAfter: DayKey.adding(-7, to: today))
            async let weeks = api.fetchWeeks(from: from, to: to)
            async let goals = api.fetchWeekGoals(from: from, to: to)
            let (newTerms, newWeeks, newGoals) = try await (terms, weeks, goals)
            cache.terms = newTerms
            cache.weeks = newWeeks
            // まだ送っていない「できた箱」は、端末側を優先する
            cache.goals = newGoals.map { goal in
                var goal = goal
                if let mine = cache.pending[goal.id] { goal.doneBoxes = mine.filter { $0 <= goal.targetCount } }
                if let mine = cache.pendingLabels?[goal.id] { goal.boxLabels = mine }   // 未送信の名前も端末側を優先
                return goal
            }
            // サーバーから消えたやることの未送信分は捨てる
            let ids = Set(newGoals.map(\.id))
            cache.pending = cache.pending.filter { ids.contains($0.key) }
            cache.pendingLabels = cache.pendingLabels?.filter { ids.contains($0.key) }
            problem = nil
            hasLoadedOnce = true
        } catch {
            problem = Self.describe(error)
        }
        save()
        rebuild()
    }

    // MARK: - 中で使う道具

    private func rebuild() {
        terms = cache.terms
        sections = WeekSection.build(weeks: cache.weeks, goals: cache.goals)
        // 「今週の計画」ウィジェットに、今週と来週の分を渡す
        WeekWidgetStore.write(Self.widgetSnapshot(sections: sections, currentWeekStart: currentWeekStart), in: widgetDir)
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(cache) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func describe(_ error: Error) -> String {
        if ErrorText.isNetworkError(error) {
            return "オフラインです。端末に保存してある計画を表示しています。"
        }
        return "同期できませんでした。\n\(ErrorText.message(for: error))"
    }
}
