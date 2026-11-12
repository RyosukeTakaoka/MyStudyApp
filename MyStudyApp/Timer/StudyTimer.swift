import Foundation
import Observation

/// 動いているタイマーの情報。アプリを終了しても消えないように、端末に保存します。
struct RunningTimer: Codable, Equatable, Sendable {
    var itemId: UUID
    var title: String
    var subject: String
    /// タイマーを始めた時刻
    var startedAt: Date
    /// 予定の終了時刻(時間なしのやることなら nil)
    var plannedEnd: Date?
    /// 自動タイマーで始まったか(自動のものは、予定の終了時刻で自動的に止まる)
    var isAuto: Bool
}

// 勉強時間を測るタイマー。
// 「始めた時刻」だけを覚えておき、経過時間は「今 − 始めた時刻」で計算します。
// こうすると、アプリを閉じていても時間が正しく進みます。
@MainActor
@Observable
final class StudyTimer {
    private(set) var running: RunningTimer?

    private let defaults: UserDefaults
    private static let runningKey = "studyTimer.running"
    private static let autoStartedKey = "studyTimer.lastAutoStarted"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.runningKey) {
            running = try? JSONDecoder().decode(RunningTimer.self, from: data)
        }
    }

    func start(_ timer: RunningTimer) {
        running = timer
        save()
    }

    /// タイマーを止めて、かかった分数を返す(動いていなければ nil)。
    /// 自動タイマーは、予定の終了時刻を過ぎていたら終了時刻までで計算する。
    func stop(now: Date) -> (itemId: UUID, minutes: Int)? {
        guard let timer = running else { return nil }
        running = nil
        save()
        var end = now
        if timer.isAuto, let plannedEnd = timer.plannedEnd, plannedEnd < now {
            end = plannedEnd
        }
        let seconds = max(0, end.timeIntervalSince(timer.startedAt))
        return (timer.itemId, Int((seconds / 60).rounded()))
    }

    /// 記録せずに止める(ログアウトのときなど)
    func cancel() {
        running = nil
        save()
    }

    /// 自動タイマーを止めるべきか(予定の終了時刻を過ぎた)
    func shouldAutoStop(now: Date) -> Bool {
        guard let timer = running, timer.isAuto, let plannedEnd = timer.plannedEnd else { return false }
        return now >= plannedEnd
    }

    /// 自動で始めるべき予定。今の時間帯の予定が未チェックで、まだ自動で始めていなければ返す
    func autoStartCandidate(items: [PlanItem], dayKey: String, nowMinutes: Int) -> PlanItem? {
        guard running == nil else { return nil }
        guard let current = NowNext.compute(items: items, nowMinutes: nowMinutes).current,
              !current.done
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
        if let running, let data = try? JSONEncoder().encode(running) {
            defaults.set(data, forKey: Self.runningKey)
        } else {
            defaults.removeObject(forKey: Self.runningKey)
        }
    }
}
