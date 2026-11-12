import Foundation
import Observation

// メイン画面に出すデータを持つ場所(React でいう状態管理のストア)。
//
// データの流れ(オフライン対応の考え方):
//
//   画面  ←─ 読む ──  端末内の保存場所(LocalStore)  ←─ 同期 ─→  サーバー(Supabase)
//         ── 書く ─→
//
//   ・画面は、いつも「端末内の保存場所」だけを読み書きする。だから電波がなくても動く
//   ・チェックやふりかえりは、まず端末に「未送信」の印を付けて保存する
//   ・同期(sync)で、未送信の変更をサーバーへ送り、サーバーの最新を端末に取りこむ
@MainActor
@Observable
final class DayStore {
    /// 同期がうまくいかなかったときの理由
    enum SyncProblem: Equatable {
        case offline            // 電波がない
        case failed(String)     // それ以外の失敗(文は画面に出す)
    }

    /// 表示している日付("2026-11-13" の形)
    private(set) var selectedDate: String
    /// 今日の日付(日付が変わったら refreshToday() で更新する)
    private(set) var today: String
    /// その日の予定とタスク(表示順にならべ済み)
    private(set) var items: [PlanItem] = []
    /// その日の目標・ふりかえり(まだ行が無い日は nil)
    private(set) var day: DayInfo?
    /// 同期中か
    private(set) var isSyncing = false
    /// 直前の同期の問題(うまくいっていれば nil)
    private(set) var syncProblem: SyncProblem?
    /// まだサーバーに送れていない変更の数
    private(set) var pendingCount = 0
    /// ふりかえりの入力欄の中身(保存前の下書き)
    var reflectionDraft = ""

    private let userId: UUID
    private let local: LocalStore
    private let api: PlanAPI
    /// 今の時刻を返す関数(テストのときに時刻を固定できるようにしている)
    private let now: () -> Date

    /// この起動中に、サーバーから読みこみ済みの日付
    private var pulledDates: Set<String> = []
    /// 電波がつながっているか(NetworkMonitor から教えてもらう)
    private var isOnline = true
    /// 実行中の同期。同期は必ず1つずつ順番に行う
    private var syncTask: Task<Void, Never>?
    /// 同期の最中に「もう一度同期して」と頼まれたか
    private var syncRequestedAgain = false
    /// 画面が閉じられているあいだ(ログアウト後など)は、同期の結果を保存しない
    private var isStopped = false

    init(userId: UUID, local: LocalStore, api: PlanAPI = RemoteAPI(), now: @escaping () -> Date = Date.init) {
        self.userId = userId
        self.local = local
        self.api = api
        self.now = now
        let today = DayKey.today(now: now())
        self.today = today
        self.selectedDate = today
        // まず端末内のデータをすぐ表示する(通信を待たない)
        reloadFromLocal(resetDraft: true)
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

    /// 表示中の日を、この起動中にサーバーから読みこめたか
    var hasPulledSelectedDate: Bool { pulledDates.contains(selectedDate) }

    /// 端末にデータが無く、最初の読みこみを待っている状態か(「読み込み中」表示に使う)
    var isWaitingForFirstLoad: Bool {
        items.isEmpty && day == nil && !hasPulledSelectedDate && syncProblem == nil
    }

    // MARK: - 日付の切り替え

    func goToPreviousDay() { select(DayKey.adding(-1, to: selectedDate)) }
    func goToNextDay() { select(DayKey.adding(1, to: selectedDate)) }
    func goToToday() { select(today) }

    /// 表示する日付を変える
    func select(_ date: String) {
        guard date != selectedDate else { return }
        // 書きかけのふりかえりが消えないように、先に保存する
        saveReflectionIfNeeded()

        selectedDate = date
        reloadFromLocal(resetDraft: true)   // 端末内のデータをすぐ表示
        requestSync()                       // 裏でサーバーの最新を取りにいく
    }

    /// アプリが前面に戻ったときに呼ぶ。日付が変わっていたら「今日」を更新する
    func refreshToday() {
        let newToday = DayKey.today(now: now())
        guard newToday != today else { return }
        let wasShowingToday = isToday
        today = newToday
        // 「今日」を見ていた場合は、新しい今日に移る(昨日の画面のまま残らないように)
        if wasShowingToday {
            select(newToday)
        }
    }

    // MARK: - チェック

    /// 行がタップされたとき: チェックを付ける/外す
    func toggle(_ item: PlanItem) {
        guard var current = local.item(id: item.id) else { return }
        current.item.done.toggle()
        current.item.doneAt = current.item.done ? now() : nil
        current.needsSync = true            // 「未送信」の印
        local.save(items: [current])        // 1. 端末に保存(電波がなくても成功する)

        reloadFromLocal()                   // 2. 画面を更新
        requestSync()                       // 3. 裏でサーバーへ送る
    }

    // MARK: - ふりかえり

    /// ふりかえりを保存する
    func saveReflection() {
        var current = local.days(on: [selectedDate]).first
            ?? LocalDay(info: DayInfo(date: selectedDate, goal: nil, reflection: nil), reflectionNeedsSync: false)
        current.info.reflection = reflectionDraft
        current.reflectionNeedsSync = true
        local.save(days: [current])

        reloadFromLocal()
        requestSync()
    }

    /// 書きかけがあるときだけ保存する(日付を変える前や、アプリを閉じるときに呼ぶ)
    func saveReflectionIfNeeded() {
        if isReflectionDirty {
            saveReflection()
        }
    }

    // MARK: - 同期

    /// 同期して、終わるまで待つ(プル・トゥ・リフレッシュ用)
    func sync() async {
        await startSync().value
    }

    /// 同期を始める(終わるのを待たない)
    func requestSync() {
        startSync()
    }

    /// 電波の状態が変わったときに呼ぶ
    func setOnline(_ online: Bool) {
        let cameBack = online && !isOnline
        isOnline = online
        if cameBack {
            requestSync()   // つながったら、たまっていた変更を送る
        }
    }

    /// 画面が出た(true)/閉じられた(false)ときに呼ぶ。
    /// 閉じられているあいだは同期を止める(ログアウト後に、同期の結果が端末に保存されないようにするため)
    func setActive(_ active: Bool) {
        isStopped = !active
    }

    /// 同期は必ず1つずつ行う。すでに実行中なら、新しく始めずに「終わったらもう1回」と予約する。
    /// (2つの同期が同時に走ると、古い通信の結果があとから届いて、新しいチェックを上書きしてしまうため)
    @discardableResult
    private func startSync() -> Task<Void, Never> {
        if let running = syncTask {
            syncRequestedAgain = true
            return running
        }
        let task = Task {
            repeat {
                syncRequestedAgain = false
                await runSyncOnce()
            } while syncRequestedAgain && !isStopped
            syncTask = nil
        }
        syncTask = task
        return task
    }

    /// 同期1回ぶん: 「送る → 受け取る」の順に行う
    private func runSyncOnce() async {
        guard !isStopped else { return }
        isSyncing = true
        defer { isSyncing = false }

        var firstError: Error?
        do {
            try await pushPendingChanges()
        } catch {
            firstError = error
        }
        // 送るのに失敗しても、原因が「電波がない」以外なら、受け取りは試す
        // (新しい予定は表示できるようにするため。未送信の変更は消えずに残る)
        if firstError == nil || !ErrorText.isNetworkError(firstError!) {
            do {
                try await pullLatest()
            } catch {
                firstError = firstError ?? error
            }
        }

        guard !isStopped else { return }
        syncProblem = firstError.flatMap { Self.describe($0, isOnline: isOnline) }
        reloadFromLocal()
    }

    /// 送る: 端末にたまっている「未送信」の変更を、サーバーへ送る
    private func pushPendingChanges() async throws {
        for pending in local.pendingItems() {
            try await api.setDone(id: pending.item.id, done: pending.item.done, doneAt: pending.item.doneAt)
            guard !isStopped else { return }
            // 送っているあいだに、もう一度タップされていないときだけ「送信済み」にする
            if var latest = local.item(id: pending.item.id),
               latest.needsSync,
               latest.item.done == pending.item.done,
               latest.item.doneAt == pending.item.doneAt {
                latest.needsSync = false
                local.save(items: [latest])
            }
        }

        for pending in local.pendingDays() {
            let text = pending.info.reflection ?? ""
            try await api.saveReflection(userId: userId, date: pending.info.date, reflection: text)
            guard !isStopped else { return }
            // 送っているあいだに、書き直されていないときだけ「送信済み」にする
            if var latest = local.days(on: [pending.info.date]).first,
               latest.reflectionNeedsSync,
               (latest.info.reflection ?? "") == text {
                latest.reflectionNeedsSync = false
                local.save(days: [latest])
            }
        }
    }

    /// 受け取る: サーバーの最新を読んで、端末内のデータに取りこむ
    private func pullLatest() async throws {
        // 表示中の日の前日〜7日後までをまとめて読む
        // (明日以降の予定も端末に入るので、オフラインでも先の日が見られる)
        let from = DayKey.adding(-1, to: selectedDate)
        let to = DayKey.adding(7, to: selectedDate)
        let dates = DayKey.keys(from: from, to: to)

        // 「async let」で2つの通信を同時に進める
        async let fetchedItems = api.fetchItems(from: from, to: to)
        async let fetchedDays = api.fetchDays(from: from, to: to)
        let (serverItems, serverDays) = try await (fetchedItems, fetchedDays)
        guard !isStopped else { return }

        // 通信が終わった「今」の端末内データと合体させる
        // (通信中にタップされたチェックは「未送信」の印が付いているので、消されない)
        let itemChanges = SyncMerge.items(server: serverItems, local: local.items(on: dates))
        local.save(items: itemChanges.save)
        local.deleteItems(ids: itemChanges.deleteIds)

        let dayChanges = SyncMerge.days(server: serverDays, local: local.days(on: dates), dates: dates)
        local.save(days: dayChanges.save)
        local.deleteDays(dates: dayChanges.deleteDates)

        pulledDates.formUnion(dates)
    }

    // MARK: - 中で使う道具

    /// 端末内のデータを読み直して、画面用の値を更新する
    private func reloadFromLocal(resetDraft: Bool = false) {
        let wasDirty = isReflectionDirty
        items = PlanItem.sortedForDisplay(local.items(on: [selectedDate]).map(\.item))
        day = local.days(on: [selectedDate]).first?.info
        // 書きかけでなければ、入力欄を保存済みの内容に合わせる
        if resetDraft || !wasDirty {
            reflectionDraft = savedReflection
        }
        pendingCount = local.pendingItems().count + local.pendingDays().count
    }

    /// エラーを、画面に出す形に分類する(お知らせするほどでもないときは nil)
    private static func describe(_ error: Error, isOnline: Bool) -> SyncProblem? {
        // 通信が途中で取り消されただけなら、問題として出さない
        if error is CancellationError || (error as? URLError)?.code == .cancelled {
            return nil
        }
        if !isOnline || ErrorText.isNetworkError(error) {
            return .offline
        }
        return .failed(ErrorText.message(for: error))
    }
}
