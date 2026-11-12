import Foundation

// days テーブルの1行(1日ごとの目標とふりかえり)を表す型。
struct DayInfo: Equatable, Codable, Sendable {
    var date: String          // "2026-11-13" の形
    var goal: String?         // 1日の目標(Claude が書く)
    var reflection: String?   // ふりかえり(アプリで自分が書く)
}
