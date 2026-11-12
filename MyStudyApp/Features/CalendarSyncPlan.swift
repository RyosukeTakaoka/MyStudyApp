import Foundation

/// カレンダーに書き出す予定1件(これから作る/直す形)
struct CalendarEventDraft: Equatable {
    var itemId: UUID
    var title: String
    var start: Date
    var end: Date
    var notes: String?
}

/// カレンダーにすでにある、このアプリが書き出した予定
struct ExistingCalendarEvent: Equatable {
    /// カレンダー側の識別名(直す・消すときに使う)
    var key: String
    /// どの予定から作ったか(URL に書いておいた id。読めなければ nil)
    var itemId: UUID?
    var title: String
    var start: Date
    var end: Date
    var notes: String?
}

// 「アプリの予定」と「カレンダーの予定」をくらべて、何を作り・直し・消すかを決める計算。
// (EventKit に頼らない計算だけにしてあるので、テストできる)
enum CalendarSyncPlan {
    /// カレンダーの予定に付ける URL。ここから元の予定の id を読みもどす
    static func url(for itemId: UUID) -> URL {
        URL(string: "mystudy://item/\(itemId.uuidString)")!
    }

    static func itemId(from url: URL?) -> UUID? {
        guard let url, url.scheme == "mystudy", url.host == "item" else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }

    /// 予定ブロックから、カレンダーに書き出す形を作る(時間なしのやることは書き出さない)
    static func drafts(items: [PlanItem], calendar: Calendar = DayKey.gregorian()) -> [CalendarEventDraft] {
        items.compactMap { item in
            guard item.isBlock,
                  let startMinutes = item.startMinutes, let endMinutes = item.endMinutes,
                  let start = DayKey.date(dayKey: item.date, minutes: startMinutes, calendar: calendar),
                  let end = DayKey.date(dayKey: item.date, minutes: endMinutes, calendar: calendar)
            else { return nil }
            let title = (item.done ? "✓ " : "") + "\(item.title)(\(item.subject))"
            let note = (item.note?.isEmpty == false) ? item.note : nil
            return CalendarEventDraft(itemId: item.id, title: title, start: start, end: end, notes: note)
        }
    }

    struct Changes: Equatable {
        var create: [CalendarEventDraft] = []
        var update: [(key: String, draft: CalendarEventDraft)] = []
        var delete: [String] = []

        static func == (a: Changes, b: Changes) -> Bool {
            a.create == b.create && a.delete == b.delete
                && a.update.map { $0.key } == b.update.map { $0.key } && a.update.map { $0.draft } == b.update.map { $0.draft }
        }
    }

    /// くらべて、作る・直す・消すものを決める
    static func diff(drafts: [CalendarEventDraft], existing: [ExistingCalendarEvent]) -> Changes {
        var changes = Changes()
        var unused = existing
        for draft in drafts {
            if let index = unused.firstIndex(where: { $0.itemId == draft.itemId }) {
                let current = unused.remove(at: index)
                let same = current.title == draft.title && current.start == draft.start
                    && current.end == draft.end && current.notes == draft.notes
                if !same {
                    changes.update.append((key: current.key, draft: draft))
                }
            } else {
                changes.create.append(draft)
            }
        }
        // 残ったもの(元の予定が消えた・重複している)は消す
        changes.delete = unused.map(\.key)
        return changes
    }
}
