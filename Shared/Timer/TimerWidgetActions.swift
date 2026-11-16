import Foundation

// ウィジェットのボタン(一時停止・再開・完了・終了)でタイマーを動かす処理。
// ウィジェットで押したことは「できごと」として共有の場所にためておき、
// アプリが記録(サーバーへ送るタイマーの区間・勉強時間)に取りこみます。

/// ウィジェットで押した1回分のできごと
struct TimerWidgetEvent: Codable, Equatable, Sendable {
    enum Action: String, Codable, Sendable {
        case pause, resume, stop
    }
    var action: Action
    var itemId: UUID
    /// 測り終えた区間(一時停止・終了のとき。記録としてサーバーへ送る)
    var session: StudySession?
    /// 終了したときの、今回の分数(予定の「実績」に足す)
    var minutes: Int?
    /// 終了したとき、予定をチェック済みにするか(完了ボタン)
    var markDone: Bool = false
}

@MainActor
enum TimerWidgetActions {
    /// アプリの中で動いたときに呼ばれる(ライブアクティビティの更新など)。アプリが起動時に設定する
    static var onChange: (@MainActor (TimerWidgetEvent) -> Void)?

    private static let eventsKey = "widget.timerEvents"

    /// 一時停止 ⇄ 再開
    static func togglePause(itemId: UUID, timer: StudyTimer, now: Date) -> TimerWidgetEvent? {
        guard let running = timer.timer(for: itemId) else { return nil }
        if running.isPaused {
            timer.resume(itemId: itemId, now: now)
            return TimerWidgetEvent(action: .resume, itemId: itemId)
        } else {
            let session = timer.pause(itemId: itemId, now: now)
            return TimerWidgetEvent(action: .pause, itemId: itemId, session: session)
        }
    }

    /// 終了(markDone なら完了としてチェックも付ける)
    static func stop(itemId: UUID, markDone: Bool, timer: StudyTimer, now: Date) -> TimerWidgetEvent? {
        guard let result = timer.stop(itemId: itemId, now: now, reason: markDone ? "done" : "stop") else { return nil }
        return TimerWidgetEvent(action: .stop, itemId: itemId, session: result.session,
                                minutes: result.minutes, markDone: markDone)
    }

    /// ボタンが押されたときの一連の処理(保存 → できごとをためる → アプリに知らせる)
    static func handle(_ event: TimerWidgetEvent?, defaults: UserDefaults = AppGroup.defaults) {
        guard let event else { return }
        append(event, defaults: defaults)
        onChange?(event)
    }

    static func append(_ event: TimerWidgetEvent, defaults: UserDefaults = AppGroup.defaults) {
        var list = pending(defaults: defaults)
        list.append(event)
        if let data = try? JSONEncoder().encode(list) {
            defaults.set(data, forKey: eventsKey)
        }
    }

    /// たまっているできごとを取り出す(取り出したら消える)
    static func takeEvents(defaults: UserDefaults = AppGroup.defaults) -> [TimerWidgetEvent] {
        let list = pending(defaults: defaults)
        defaults.removeObject(forKey: eventsKey)
        return list
    }

    private static func pending(defaults: UserDefaults) -> [TimerWidgetEvent] {
        guard let data = defaults.data(forKey: eventsKey) else { return [] }
        return (try? JSONDecoder().decode([TimerWidgetEvent].self, from: data)) ?? []
    }
}

extension Notification.Name {
    /// ウィジェットのボタンでタイマーが変わった(アプリの画面が読み直す合図)
    static let studyTimerChangedFromWidget = Notification.Name("studyTimerChangedFromWidget")
}
