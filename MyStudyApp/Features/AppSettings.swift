import Foundation

// アプリの設定の保存名(@AppStorage で使う)
enum AppSettings {
    /// 予定の時間になったら自動でタイマーを始めるか
    static let autoTimerKey = "settings.autoTimer"
    /// 予定の開始時刻に通知するか
    static let remindersKey = "settings.reminders"
}
