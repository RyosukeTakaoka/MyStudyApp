import Foundation
import WidgetKit

// アプリ → ウィジェットへのデータの受け渡し係。
enum WidgetBridge {
    /// 新しいデータを共有フォルダに書いて、ウィジェットに描き直しを頼む
    static func publish(_ snapshot: WidgetSnapshot) {
        SharedStore.writeSnapshot(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// ログアウトしたとき: ウィジェットのデータを空にする
    static func clear() {
        SharedStore.writeSnapshot(.empty)
        _ = SharedStore.takePendingToggles()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
