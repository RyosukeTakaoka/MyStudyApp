import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

// 「今週の計画」ウィジェットに渡すデータ(週・月タブの今週と来週の分)。
// アプリが共有フォルダに書き、ウィジェットが読みます。
struct WeekWidgetSnapshot: Codable, Equatable, Sendable {
    struct Goal: Codable, Equatable, Sendable {
        var group: String
        var title: String
        /// 箱の数(例 数学 1〜12 なら 12)
        var target: Int
        /// 緑にした箱の番号
        var doneBoxes: [Int]

        var done: Int { doneBoxes.count }
    }

    struct Week: Codable, Equatable, Sendable {
        var weekStart: String
        var label: String?
        var subtitle: String?
        var events: [String]
        var goals: [Goal]

        var done: Int { goals.reduce(0) { $0 + min($1.done, $1.target) } }
        var total: Int { goals.reduce(0) { $0 + $1.target } }
        /// 例 "11/16(月)〜11/22(日)"
        var rangeText: String {
            "\(DayKey.shortText(weekStart))〜\(DayKey.shortText(DayKey.adding(6, to: weekStart)))"
        }
    }

    var weeks: [Week]

    static let empty = WeekWidgetSnapshot(weeks: [])

    /// その日をふくむ週(無ければ nil)
    func week(containing dayKey: String) -> Week? {
        let monday = DayKey.mondayOfWeek(dayKey)
        return weeks.first { $0.weekStart == monday }
    }
}

/// 共有フォルダの読み書き
enum WeekWidgetStore {
    static let kind = "WeekWidget"
    private static let file = "week-widget.json"

    static func read(in dir: URL? = AppGroup.containerURL) -> WeekWidgetSnapshot {
        guard let dir, let data = try? Data(contentsOf: dir.appendingPathComponent(file)),
              let snapshot = try? JSONDecoder().decode(WeekWidgetSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }

    /// 書く(前と同じなら何もしない。ウィジェットの描き直しを頼みすぎないように)
    static func write(_ snapshot: WeekWidgetSnapshot, in dir: URL? = AppGroup.containerURL) {
        guard let dir, read(in: dir) != snapshot, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: dir.appendingPathComponent(file), options: .atomic)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
        #endif
    }
}
