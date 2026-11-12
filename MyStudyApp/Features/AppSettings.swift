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
}
