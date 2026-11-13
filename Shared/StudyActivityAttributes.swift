#if canImport(ActivityKit)
import ActivityKit
import Foundation

// ライブアクティビティ(ロック画面・ダイナミックアイランド)に渡すデータの形。
// アプリ(表示を始める側)とウィジェット(表示する側)の両方で使います。
struct StudyActivityAttributes: ActivityAttributes {
    /// 表示中に変わりうる値
    struct ContentState: Codable, Hashable {
        var title: String
        var subject: String
        /// 数え始めた時刻(ここからの経過時間を表示する。一時停止した分だけ後ろにずらしてある)
        var startedAt: Date
        /// 一時停止中なら、その時点の経過秒数(動いているときは nil)
        var pausedElapsed: Double?
        /// 予定の終了時刻(進み具合のバーに使う。無ければ nil)
        var plannedEnd: Date?
        var nextTitle: String?
        var nextStart: Date?
    }

    /// 表示中に変わらない値
    var itemId: String
}
#endif
