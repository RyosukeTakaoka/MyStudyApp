#if canImport(AppIntents) && canImport(ActivityKit)
import AppIntents
import Foundation

// タイマーのウィジェットのボタンを押したときに動く処理。
// LiveActivityIntent にすると、ウィジェットではなく「アプリ」の中で動きます
// (アプリが閉じていても、裏で起こして動かしてくれる)。
// そのため、ライブアクティビティ(ロック画面の経過時間)もいっしょに直せます。

/// 一時停止 ⇄ 再開
struct ToggleTimerPauseIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "タイマーを一時停止・再開"
    static var isDiscoverable: Bool = false

    @Parameter(title: "予定のID")
    var itemId: String

    init() {}

    init(itemId: UUID) {
        self.itemId = itemId.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: itemId) else { return .result() }
        let timer = StudyTimer()   // 共有の場所に保存してあるタイマーを読む
        TimerWidgetActions.handle(TimerWidgetActions.togglePause(itemId: id, timer: timer, now: Date()))
        return .result()
    }
}

/// 終了(記録して終了)・完了(記録してチェック)
struct StopTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "タイマーを終了"
    static var isDiscoverable: Bool = false

    @Parameter(title: "予定のID")
    var itemId: String

    @Parameter(title: "完了にする")
    var markDone: Bool

    init() {}

    init(itemId: UUID, markDone: Bool) {
        self.itemId = itemId.uuidString
        self.markDone = markDone
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: itemId) else { return .result() }
        let timer = StudyTimer()
        TimerWidgetActions.handle(TimerWidgetActions.stop(itemId: id, markDone: markDone, timer: timer, now: Date()))
        return .result()
    }
}
#endif
