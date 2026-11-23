import Foundation

// days テーブルの1行(1日ごとの目標とふりかえり)を表す型。
struct DayInfo: Equatable, Codable, Sendable {
    var date: String          // "2026-11-13" の形
    var goal: String?         // 1日の目標(Claude が書く)
    var reflection: String?   // ふりかえり(アプリで自分が書く)
    var targetMinutes: Int? = nil   // その日の勉強の目標時間(分)。nil なら 平日4時間・土日8時間
    var coachNote: String? = nil    // Claude からのひとこと(目標の下に出す)

    enum CodingKeys: String, CodingKey {
        case date, goal, reflection
        case targetMinutes = "target_minutes"
        case coachNote = "coach_note"
    }

    init(date: String, goal: String?, reflection: String?, targetMinutes: Int? = nil, coachNote: String? = nil) {
        self.date = date
        self.goal = goal
        self.reflection = reflection
        self.targetMinutes = targetMinutes
        self.coachNote = coachNote
    }

    /// サーバーや前の版で保存したもの(新しい列が無い)も読めるようにする
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(String.self, forKey: .date)
        goal = try c.decodeIfPresent(String.self, forKey: .goal)
        reflection = try c.decodeIfPresent(String.self, forKey: .reflection)
        targetMinutes = try? c.decodeIfPresent(Int.self, forKey: .targetMinutes)
        coachNote = try? c.decodeIfPresent(String.self, forKey: .coachNote)
    }

    /// その日の勉強の目標時間(分)。決めていなければ 平日240分・土日480分
    static func defaultTargetMinutes(for dayKey: String) -> Int {
        let calendar = DayKey.gregorian()
        guard let date = DayKey.date(dayKey: dayKey, minutes: 12 * 60, calendar: calendar) else { return 240 }
        let weekday = calendar.component(.weekday, from: date)   // 1 = 日曜, 7 = 土曜
        return (weekday == 1 || weekday == 7) ? 480 : 240
    }

    var effectiveTargetMinutes: Int { targetMinutes ?? Self.defaultTargetMinutes(for: date) }
}
