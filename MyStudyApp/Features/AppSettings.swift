import Foundation

// アプリの設定の保存名(@AppStorage で使う)
enum AppSettings {
    /// 予定の時間になったら自動でタイマーを始めるか
    static let autoTimerKey = "settings.autoTimer"
    /// 予定の開始時刻に通知するか
    static let remindersKey = "settings.reminders"
    /// タイマー中は集中モード(スクリーンタイム)にするか
    static let focusDuringTimerKey = "settings.focusDuringTimer"
    /// 予定ブロックの時間は自動で集中モードにするか
    static let focusAutoBlocksKey = "settings.focusAutoBlocks"
    /// iPhone のカレンダーと連携するか
    static let calendarSyncKey = "settings.calendarSync"
    /// 「週・月」タブの箱に、番号の代わりに曜日(名前)を出すか
    static let boxWeekdaysKey = "settings.boxWeekdays"

    /// 「自動タイマーはオフ・予定の時間は自動で集中モード」に1回だけ切りかえたか
    private static let focusAutoMigrationKey = "settings.migrated.focusAutoInsteadOfAutoTimer"

    /// 自動タイマーは使わず、予定の時間に自動で集中モード(スクリーンタイム)にする設定へ、1回だけ切りかえる。
    /// (ユーザーの希望。切りかえたあとは、メニューや集中モードの設定で自由に戻せる)
    static func applyFocusAutoDefaultsOnce(_ defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: focusAutoMigrationKey) else { return }
        defaults.set(false, forKey: autoTimerKey)
        defaults.set(true, forKey: focusAutoBlocksKey)
        defaults.set(true, forKey: focusAutoMigrationKey)
    }
}
