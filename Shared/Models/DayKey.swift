import Foundation

// 日付を "2026-11-13" の形の文字(このアプリでは「日付キー」と呼びます)で扱うための道具。
//
// なぜ Date 型ではなく文字で持つのか:
//   データベースの date 列は「時刻のない日付」なので、文字のまま扱うほうが
//   時差(タイムゾーン)のずれによるバグが起きにくいためです。
enum DayKey {
    /// 西暦のカレンダー。iPhone の設定が和暦でも「2026」のように西暦で計算するために固定している
    static func gregorian(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// Date → "2026-11-13"
    static func string(from date: Date, calendar: Calendar = gregorian()) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// "2026-11-13" → Date(その日の正午)。読めない形なら nil
    static func date(from key: String, calendar: Calendar = gregorian()) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        // 正午にしておくと、日付の足し算でずれにくい
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    /// 今日の日付キー
    static func today(now: Date = Date(), calendar: Calendar = gregorian()) -> String {
        string(from: now, calendar: calendar)
    }

    /// 日付キーに日数を足す(マイナスなら引く)。"2026-11-30" + 1 → "2026-12-01"
    static func adding(_ days: Int, to key: String, calendar: Calendar = gregorian()) -> String {
        guard let base = date(from: key, calendar: calendar),
              let moved = calendar.date(byAdding: .day, value: days, to: base)
        else { return key }
        return string(from: moved, calendar: calendar)
    }

    /// from から to までの日付キーを全部ならべる(両端をふくむ)
    static func keys(from: String, to: String, calendar: Calendar = gregorian()) -> [String] {
        var result: [String] = []
        var current = from
        // 文字のままでも "2026-11-13" < "2026-11-14" と正しく大小をくらべられる
        while current <= to && result.count < 366 {
            result.append(current)
            current = adding(1, to: current, calendar: calendar)
        }
        return result
    }

    /// 画面に出す日付(例: 11月13日(金))
    static func displayText(_ key: String, calendar: Calendar = gregorian()) -> String {
        guard let date = date(from: key, calendar: calendar) else { return key }
        let c = calendar.dateComponents([.month, .day, .weekday], from: date)
        let weekdays = ["日", "月", "火", "水", "木", "金", "土"]
        let weekday = weekdays[((c.weekday ?? 1) - 1) % 7]
        return "\(c.month ?? 0)月\(c.day ?? 0)日(\(weekday))"
    }

    /// 短い表示(例: 11/13(金))
    static func shortText(_ key: String, calendar: Calendar = gregorian()) -> String {
        guard let date = date(from: key, calendar: calendar) else { return key }
        let c = calendar.dateComponents([.month, .day, .weekday], from: date)
        let weekdays = ["日", "月", "火", "水", "木", "金", "土"]
        return "\(c.month ?? 0)/\(c.day ?? 0)(\(weekdays[((c.weekday ?? 1) - 1) % 7]))"
    }

    /// その日がふくまれる週の月曜日
    static func mondayOfWeek(_ key: String, calendar: Calendar = gregorian()) -> String {
        guard let date = date(from: key, calendar: calendar) else { return key }
        let weekday = calendar.component(.weekday, from: date)   // 1 = 日曜, 2 = 月曜
        return adding(-((weekday + 5) % 7), to: key, calendar: calendar)
    }

    /// 今日から見た呼び方(今日・明日・昨日)。それ以外は nil
    static func relativeLabel(_ key: String, today: String, calendar: Calendar = gregorian()) -> String? {
        switch key {
        case today: return "今日"
        case adding(1, to: today, calendar: calendar): return "明日"
        case adding(-1, to: today, calendar: calendar): return "昨日"
        default: return nil
        }
    }

    /// 日付キーと「0時からの分数」から、その瞬間の Date を作る("2026-11-13" + 990 → 11/13 16:30)
    static func date(dayKey: String, minutes: Int, calendar: Calendar = gregorian()) -> Date? {
        guard let noon = date(from: dayKey, calendar: calendar) else { return nil }
        return calendar.startOfDay(for: noon).addingTimeInterval(TimeInterval(minutes * 60))
    }

    /// 次に日付が変わる瞬間(今夜の 0:00)までの秒数
    static func secondsUntilNextDay(now: Date = Date(), calendar: Calendar = gregorian()) -> TimeInterval {
        let startOfToday = calendar.startOfDay(for: now)
        guard let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) else {
            return 24 * 60 * 60
        }
        return startOfTomorrow.timeIntervalSince(now)
    }

    /// 今の時刻を「0時からの分数」で返す(16:30 → 990)
    static func minutesOfDay(_ date: Date, calendar: Calendar = gregorian()) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}
