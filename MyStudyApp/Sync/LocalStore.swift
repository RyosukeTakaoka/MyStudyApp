import Foundation

// 端末内の保存場所(キャッシュ)の「約束ごと」を決めるファイル。
//
// protocol は「この機能を持っていること」という約束だけを書いたものです
// (TypeScript の interface と同じ考え方)。
// 本物は SwiftData を使う SwiftDataStore ですが、約束を分けておくことで、
// 同期のロジックを SwiftData 抜きでテストできるようにしています。

/// 端末に保存している予定1件。needsSync = まだサーバーに送っていない変更があるか
struct LocalItem: Equatable, Sendable {
    var item: PlanItem
    var needsSync: Bool
}

/// 端末に保存している1日の情報。reflectionNeedsSync = ふりかえりをまだサーバーに送っていないか
struct LocalDay: Equatable, Sendable {
    var info: DayInfo
    var reflectionNeedsSync: Bool
}

@MainActor
protocol LocalStore: AnyObject {
    /// 指定した日付の予定を全部読む
    func items(on dates: [String]) -> [LocalItem]
    /// id で予定を1件読む
    func item(id: UUID) -> LocalItem?
    /// 指定した日付の「1日の情報」を読む
    func days(on dates: [String]) -> [LocalDay]
    /// まだサーバーに送っていない変更がある予定
    func pendingItems() -> [LocalItem]
    /// まだサーバーに送っていないふりかえりがある日
    func pendingDays() -> [LocalDay]
    /// 保存する(同じ id があれば上書き、なければ追加)
    func save(items: [LocalItem])
    /// 保存する(同じ日付があれば上書き、なければ追加)
    func save(days: [LocalDay])
    func deleteItems(ids: [UUID])
    func deleteDays(dates: [String])
    /// 全部消す(ログアウトのとき)
    func deleteEverything()
}
