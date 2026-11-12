import Foundation

// items テーブルの1行を表す型。
// Codable を付けると、Supabase から届く JSON と自動で相互変換できます。
struct PlanItem: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var date: String          // "2026-11-13" の形
    var kind: String          // "block" = 時間つきの予定 / "task" = 時間なしのやること
    var startTime: String?    // "16:30:00" の形(block のみ)
    var endTime: String?      // "17:30:00" の形(block のみ)
    var title: String
    var subject: String       // 科目(例: 鑑定理論)
    var sortOrder: Int
    var source: String        // "claude" または "app"
    var done: Bool
    var doneAt: Date?
    var actualMinutes: Int?
    var note: String?

    // Swift 側の名前(startTime)と、データベース側の列名(start_time)の対応表
    enum CodingKeys: String, CodingKey {
        case id, date, kind, title, subject, source, done, note
        case startTime = "start_time"
        case endTime = "end_time"
        case sortOrder = "sort_order"
        case doneAt = "done_at"
        case actualMinutes = "actual_minutes"
    }
}

extension PlanItem {
    /// 時間つきの予定か
    var isBlock: Bool { kind == "block" }

    /// 開始時刻を「0時からの分数」で表したもの(16:30 → 990)
    var startMinutes: Int? { TimeOfDay.minutes(from: startTime) }

    /// 終了時刻を「0時からの分数」で表したもの。
    /// 終了が開始より前(日付をまたぐ予定)のときは、その日の終わり(24:00)までとして扱う
    var endMinutes: Int? {
        guard let end = TimeOfDay.minutes(from: endTime) else { return nil }
        if let start = startMinutes, end <= start { return 24 * 60 }
        return end
    }

    /// 画面に出す時刻の文字(例: 16:30〜17:30)。task のときは nil
    var timeRangeText: String? {
        guard let start = TimeOfDay.minutes(from: startTime) else { return nil }
        guard let end = TimeOfDay.minutes(from: endTime) else { return TimeOfDay.text(start) }
        return "\(TimeOfDay.text(start))〜\(TimeOfDay.text(end))"
    }

    /// 画面に出す順番に並べる。予定(block)は開始時刻順、やること(task)は sort_order 順。
    static func sortedForDisplay(_ items: [PlanItem]) -> [PlanItem] {
        items.sorted { a, b in
            // 並べる基準を「タプル」にして、左から順にくらべる
            let keyA = (a.isBlock ? 0 : 1, a.startMinutes ?? 0, a.sortOrder, a.title, a.id.uuidString)
            let keyB = (b.isBlock ? 0 : 1, b.startMinutes ?? 0, b.sortOrder, b.title, b.id.uuidString)
            return keyA < keyB
        }
    }
}

// 時刻の文字("16:30:00")と分数(990)を変換する道具
enum TimeOfDay {
    /// "16:30" や "16:30:00" → 990。読めない形なら nil
    static func minutes(from text: String?) -> Int? {
        guard let text else { return nil }
        let parts = text.split(separator: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...24).contains(hour), (0...59).contains(minute)
        else { return nil }
        return hour * 60 + minute
    }

    /// 990 → "16:30"
    static func text(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}
