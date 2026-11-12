import Foundation

/// 予約する通知1件
struct Reminder: Equatable {
    let id: String
    let fireDate: Date
    let title: String
    let body: String
}

// 「予定の開始時刻に通知」の中身を決める計算(実際の予約は NotificationScheduler が行う)
enum ReminderPlan {
    static let idPrefix = "plan-"

    /// 未チェックの予定ブロックのうち、これから始まるものの通知を作る。
    /// iPhone は1つのアプリにつき64件までしか通知を予約できないので、早い順に limit 件まで
    static func make(items: [PlanItem], now: Date, calendar: Calendar = DayKey.gregorian(), limit: Int = 60) -> [Reminder] {
        let reminders: [Reminder] = items.compactMap { item in
            guard item.isBlock, !item.done,
                  let start = item.startMinutes,
                  let fireDate = DayKey.date(dayKey: item.date, minutes: start, calendar: calendar),
                  fireDate > now
            else { return nil }
            let body = [item.timeRangeText, item.subject].compactMap { $0 }.joined(separator: " ・ ")
            return Reminder(id: idPrefix + item.id.uuidString, fireDate: fireDate, title: item.title, body: body)
        }
        return Array(reminders.sorted { $0.fireDate < $1.fireDate }.prefix(limit))
    }
}
