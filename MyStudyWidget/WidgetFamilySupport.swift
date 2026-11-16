import WidgetKit

// iOS 27 で増えた、iPhone の特大ウィジェット(たて長・ホーム画面1ページ分)の扱い。
// 古い Xcode(27 より前)はこの大きさの名前を知らないので、#if compiler でとばします。
extension WidgetFamily {
    /// 特大(たて長)か。iOS 27 より前では、いつも false
    var isExtraLargePortrait: Bool {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            return self == .systemExtraLargePortrait
        }
        #endif
        return false
    }

    /// 大きさの一覧に、使えるなら特大(たて長)を足す
    static func withExtraLargePortrait(_ list: [WidgetFamily]) -> [WidgetFamily] {
        var list = list
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            list.append(.systemExtraLargePortrait)
        }
        #endif
        return list
    }
}

/// 経過時間の文字(例 1:05:09 / 12:30)
enum ElapsedFormat {
    static func text(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
