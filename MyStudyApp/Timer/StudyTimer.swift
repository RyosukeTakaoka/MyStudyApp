import Foundation
import Observation

/// 動いているタイマーの情報。アプリを終了しても消えないように、端末に保存します。
///
/// 一時停止ができるように、時間は次の2つに分けて覚えます。
///   ・accumulatedSeconds … これまでに測り終えた秒数(一時停止までの分の合計)
///   ・startedAt          … 今の「測っている区間」を始めた(再開した)時刻
/// 経過時間 = accumulatedSeconds + (動いていれば 今 − startedAt)
struct RunningTimer: Codable, Equatable, Sendable {
    var itemId: UUID
    var title: String
    var subject: String
    /// 今の区間を始めた(再開した)時刻
    var startedAt: Date
    /// 予定の終了時刻(時間なしのやることなら nil)
    var plannedEnd: Date?
    /// 自動タイマーで始まったか(自動のものは、予定の終了時刻で自動的に止まる)
    var isAuto: Bool
    /// 一時停止までに測った秒数の合計
    var accumulatedSeconds: TimeInterval = 0
    /// 一時停止した時刻(動いているときは nil)
    var pausedAt: Date? = nil
    /// このタイマーを始める前に、同じ予定ですでに記録してあった秒数(表示に足すだけで、記録はしない)
    var priorSeconds: TimeInterval = 0
    /// その予定の日付(記録に残すため)
    var itemDate: String? = nil

    var isPaused: Bool { pausedAt != nil }

    /// 今の区間(startedAt 〜 end)の記録を作る。長さが0なら nil
    func session(endingAt end: Date, reason: String) -> StudySession? {
        guard end > startedAt else { return nil }
        return StudySession(itemId: itemId, itemDate: itemDate, title: title, subject: subject,
                            startedAt: startedAt, endedAt: end, endReason: reason)
    }

    /// 画面に出す秒数(これまでの記録 + 今回)
    func displaySeconds(now: Date) -> TimeInterval { priorSeconds + elapsedSeconds(now: now) }

    /// 画面で「この時刻から数え始めた」とみなす時刻(これまでの記録の分も、前にずらす)
    var displayStart: Date { virtualStart.addingTimeInterval(-priorSeconds) }

    /// 経過した秒数
    func elapsedSeconds(now: Date) -> TimeInterval {
        guard !isPaused else { return accumulatedSeconds }
        return accumulatedSeconds + max(0, now.timeIntervalSince(startedAt))
    }

    /// 「この時刻から数え始めた」とみなせる時刻(表示で、経過時間を自動で数えるために使う)。
    /// 一時停止していた分だけ、本当の開始より後ろにずれる
    var virtualStart: Date { startedAt.addingTimeInterval(-accumulatedSeconds) }
}

extension RunningTimer {
    /// 古い版で保存したタイマー(一時停止の項目がない)も読めるようにする
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        itemId = try c.decode(UUID.self, forKey: .itemId)
        title = try c.decode(String.self, forKey: .title)
        subject = try c.decode(String.self, forKey: .subject)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        plannedEnd = try c.decodeIfPresent(Date.self, forKey: .plannedEnd)
        isAuto = try c.decodeIfPresent(Bool.self, forKey: .isAuto) ?? false
        accumulatedSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .accumulatedSeconds) ?? 0
        pausedAt = try c.decodeIfPresent(Date.self, forKey: .pausedAt)
        priorSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .priorSeconds) ?? 0
        itemDate = try c.decodeIfPresent(String.self, forKey: .itemDate)
    }
}

// 勉強時間を測るタイマー。いくつでも同時に動かせる(例: 夕食を食べながら Anki と、ほかの予定)。
// 予定1つにつき、タイマーは1つまで。
// 「始めた時刻」だけを覚えておき、経過時間は「今 − 始めた時刻」で計算します。
// こうすると、アプリを閉じていても時間が正しく進みます。
@MainActor
@Observable
final class StudyTimer {
    /// 動いている(一時停止中もふくむ)タイマー。始めた順
    private(set) var timers: [RunningTimer] = []

    private let defaults: UserDefaults
    private static let timersKey = "studyTimer.timers"
    /// 前の版(タイマーが1つだけだったころ)の保存場所
    private static let legacyRunningKey = "studyTimer.running"
    private static let autoStartedKey = "studyTimer.lastAutoStarted"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.timersKey),
           let saved = try? JSONDecoder().decode([RunningTimer].self, from: data) {
            timers = saved
        } else if let data = defaults.data(forKey: Self.legacyRunningKey),
                  let old = try? JSONDecoder().decode(RunningTimer.self, from: data) {
            // 前の版で動いていたタイマーを引きつぐ
            timers = [old]
            defaults.removeObject(forKey: Self.legacyRunningKey)
            save()
        }
    }

    /// その予定のタイマー(無ければ nil)
    func timer(for itemId: UUID) -> RunningTimer? {
        timers.first { $0.itemId == itemId }
    }

    /// 一時停止していないタイマー
    var activeTimers: [RunningTimer] { timers.filter { !$0.isPaused } }

    /// タイマーを始める(同じ予定のタイマーがすでにあれば、置きかえる)
    func start(_ timer: RunningTimer) {
        timers.removeAll { $0.itemId == timer.itemId }
        timers.append(timer)
        save()
    }

    /// 一時停止する(それまでの時間は覚えておく)。止めた区間の記録を返す
    @discardableResult
    func pause(itemId: UUID, now: Date) -> StudySession? {
        guard let index = timers.firstIndex(where: { $0.itemId == itemId }), !timers[index].isPaused else { return nil }
        var timer = timers[index]
        let session = timer.session(endingAt: now, reason: "pause")
        timer.accumulatedSeconds = timer.elapsedSeconds(now: now)
        timer.pausedAt = now
        timers[index] = timer
        save()
        return session
    }

    /// 再開する(0からではなく、止めたところから続きを数える)
    func resume(itemId: UUID, now: Date) {
        guard let index = timers.firstIndex(where: { $0.itemId == itemId }), timers[index].isPaused else { return }
        timers[index].startedAt = now
        timers[index].pausedAt = nil
        save()
    }

    /// タイマーを止めて、かかった分数を返す(動いていなければ nil)。一時停止していた時間はふくまない。
    /// 返すのは「今回」の分だけ(これまでの記録 priorSeconds は、すでに保存してあるのでふくめない)。
    /// 自動タイマーは、予定の終了時刻を過ぎていたら終了時刻までで計算する。
    /// reason: 止めた理由(stop / done / auto)。動いていた区間の記録も返す(一時停止中なら nil)
    func stop(itemId: UUID, now: Date, reason: String = "stop") -> (itemId: UUID, minutes: Int, session: StudySession?)? {
        guard let index = timers.firstIndex(where: { $0.itemId == itemId }) else { return nil }
        let timer = timers.remove(at: index)
        save()
        var end = now
        if timer.isAuto, let plannedEnd = timer.plannedEnd, plannedEnd < now {
            end = plannedEnd
        }
        let seconds = timer.isPaused
            ? timer.accumulatedSeconds
            : timer.accumulatedSeconds + max(0, end.timeIntervalSince(timer.startedAt))
        let session = timer.isPaused ? nil : timer.session(endingAt: end, reason: reason)
        return (timer.itemId, Int((seconds / 60).rounded()), session)
    }

    /// 記録せずに全部止める(ログアウトのときなど)
    func cancelAll() {
        timers = []
        save()
    }

    /// 予定の終了時刻を過ぎた、自動タイマーの予定
    func itemIdsToAutoStop(now: Date) -> [UUID] {
        timers.filter { timer in
            guard timer.isAuto, let plannedEnd = timer.plannedEnd else { return false }
            return now >= plannedEnd
        }.map(\.itemId)
    }

    /// 自動で始めるべき予定。今の時間帯の予定が未チェックで、タイマーがまだ無く、まだ自動で始めていなければ返す
    func autoStartCandidate(items: [PlanItem], dayKey: String, nowMinutes: Int) -> PlanItem? {
        guard let current = NowNext.compute(items: items, nowMinutes: nowMinutes).current,
              !current.done,
              timer(for: current.id) == nil
        else { return nil }
        // 同じ予定で2回目は自動で始めない(自分で止めたのに、また始まらないように)
        guard defaults.string(forKey: Self.autoStartedKey) != Self.autoKey(dayKey, current.id) else { return nil }
        return current
    }

    func markAutoStarted(_ item: PlanItem, dayKey: String) {
        defaults.set(Self.autoKey(dayKey, item.id), forKey: Self.autoStartedKey)
    }

    private static func autoKey(_ dayKey: String, _ id: UUID) -> String {
        "\(dayKey)|\(id.uuidString)"
    }

    private func save() {
        if let data = try? JSONEncoder().encode(timers) {
            defaults.set(data, forKey: Self.timersKey)
        }
    }
}
