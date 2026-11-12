import Foundation
import UserNotifications

// 予定の開始時刻に通知を出すための予約係。
@MainActor
enum NotificationScheduler {
    /// 通知の許可を求める(初回だけ iPhone の確認画面が出る)。許可されたら true
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// このアプリが予約した通知を全部入れかえる
    static func reschedule(_ reminders: [Reminder]) async {
        let center = UNUserNotificationCenter.current()
        await removeAll()
        let calendar = DayKey.gregorian()
        for reminder in reminders {
            let content = UNMutableNotificationContent()
            content.title = "\(reminder.title) の時間です"
            content.body = reminder.body
            content.sound = .default
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
        }
    }

    /// このアプリが予約した通知を全部消す
    static func removeAll() async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(ReminderPlan.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}
