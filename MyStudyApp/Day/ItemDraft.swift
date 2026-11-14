import Foundation

/// 編集画面で入力中の内容
struct ItemDraft: Equatable {
    var date: String
    var isBlock = true
    var title = ""
    var subject = "その他"
    var note = ""
    var start: Date
    var hasEnd = true
    var end: Date

    static let standardSubjects = ["鑑定理論", "行政法規", "民法", "経済", "会計", "学校", "その他"]

    /// 科目の選択肢(いつもの科目 + 今の科目がそれ以外なら、それも)
    static func subjects(including current: String) -> [String] {
        standardSubjects.contains(current) ? standardSubjects : standardSubjects + [current]
    }

    /// 足すとき: 今の時刻の次のきりのよい時刻から1時間
    init(date: String, now: Date = Date()) {
        self.date = date
        let minutes = (DayKey.minutesOfDay(now) / 15 + 1) * 15
        let startMinutes = min(minutes, 23 * 60)
        start = DayKey.date(dayKey: date, minutes: startMinutes) ?? now
        end = DayKey.date(dayKey: date, minutes: min(startMinutes + 60, 23 * 60 + 59)) ?? now
    }

    /// 直すとき: 元の予定から
    init(item: PlanItem) {
        date = item.date
        isBlock = item.isBlock
        title = item.title
        subject = item.subject
        note = item.note ?? ""
        let startMinutes = item.startMinutes ?? 9 * 60
        start = DayKey.date(dayKey: item.date, minutes: startMinutes) ?? Date()
        hasEnd = item.endMinutes != nil || !item.isBlock
        end = DayKey.date(dayKey: item.date, minutes: TimeOfDay.minutes(from: item.endTime) ?? min(startMinutes + 60, 23 * 60 + 59)) ?? Date()
    }

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// 保存できない理由(問題なければ nil)
    var problem: String? {
        if trimmedTitle.isEmpty { return "題名を入れてください。" }
        if isBlock && hasEnd && DayKey.minutesOfDay(end) <= DayKey.minutesOfDay(start) {
            return "終了は開始より後の時刻にしてください。"
        }
        return nil
    }

    /// データベースに入れる形の時刻("16:30:00")
    var startTimeText: String? { isBlock ? Self.timeText(start) : nil }
    var endTimeText: String? { isBlock && hasEnd ? Self.timeText(end) : nil }
    var noteOrNil: String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func timeText(_ date: Date) -> String {
        let minutes = DayKey.minutesOfDay(date)
        return String(format: "%02d:%02d:00", minutes / 60, minutes % 60)
    }

    /// 元の予定に、入力した内容を当てはめる
    func applied(to item: PlanItem) -> PlanItem {
        var item = item
        item.kind = isBlock ? "block" : "task"
        item.startTime = startTimeText
        item.endTime = endTimeText
        item.title = trimmedTitle
        item.subject = subject
        item.note = noteOrNil
        return item
    }
}
