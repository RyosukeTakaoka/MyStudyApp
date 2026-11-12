import Foundation

/// カレンダーの1日ぶんの集計
struct DayStat: Equatable {
    var total = 0
    var done = 0
    var minutes = 0

    /// 達成率(0〜1)
    var ratio: Double { total == 0 ? 0 : Double(done) / Double(total) }
}

/// 科目ごとの勉強時間
struct SubjectMinutes: Identifiable, Equatable {
    var subject: String
    var minutes: Int
    var id: String { subject }
}

// カレンダー画面の計算(画面の部品から分けて、テストできるようにしている)
enum CalendarMath {
    /// その日がふくまれる月の1日("2026-11-13" → "2026-11-01")
    static func monthStart(of key: String) -> String {
        String(key.prefix(8)) + "01"
    }

    /// 月を進める・戻す("2026-12-01" + 1 → "2027-01-01")
    static func addingMonths(_ months: Int, to monthStart: String, calendar: Calendar = DayKey.gregorian()) -> String {
        guard let date = DayKey.date(from: monthStart, calendar: calendar),
              let moved = calendar.date(byAdding: .month, value: months, to: date)
        else { return monthStart }
        return Self.monthStart(of: DayKey.string(from: moved, calendar: calendar))
    }

    /// その月の最後の日
    static func monthEnd(_ monthStart: String, calendar: Calendar = DayKey.gregorian()) -> String {
        DayKey.adding(-1, to: addingMonths(1, to: monthStart, calendar: calendar), calendar: calendar)
    }

    /// カレンダーのマス目(日曜はじまり)。1日より前の空きマスは nil
    static func grid(monthStart: String, calendar: Calendar = DayKey.gregorian()) -> [String?] {
        guard let first = DayKey.date(from: monthStart, calendar: calendar) else { return [] }
        let weekday = calendar.component(.weekday, from: first)   // 1 = 日曜
        let days = DayKey.keys(from: monthStart, to: monthEnd(monthStart, calendar: calendar), calendar: calendar)
        return Array(repeating: nil, count: weekday - 1) + days.map { Optional($0) }
    }

    /// "2026年11月"
    static func monthTitle(_ monthStart: String) -> String {
        let parts = monthStart.split(separator: "-").compactMap { Int($0) }
        guard parts.count >= 2 else { return monthStart }
        return "\(parts[0])年\(parts[1])月"
    }

    /// 日付ごとの集計
    static func stats(_ items: [PlanItem]) -> [String: DayStat] {
        var result: [String: DayStat] = [:]
        for item in items {
            var stat = result[item.date] ?? DayStat()
            stat.total += 1
            if item.done { stat.done += 1 }
            stat.minutes += item.actualMinutes ?? 0
            result[item.date] = stat
        }
        return result
    }

    /// 科目ごとの勉強時間(多い順)。時間の記録が無い科目は出さない
    static func minutesBySubject(_ items: [PlanItem]) -> [SubjectMinutes] {
        var totals: [String: Int] = [:]
        for item in items {
            totals[item.subject, default: 0] += item.actualMinutes ?? 0
        }
        return totals
            .filter { $0.value > 0 }
            .map { SubjectMinutes(subject: $0.key, minutes: $0.value) }
            .sorted { $0.minutes != $1.minutes ? $0.minutes > $1.minutes : $0.subject < $1.subject }
    }
}
