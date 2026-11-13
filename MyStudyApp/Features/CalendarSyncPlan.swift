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
                  let startMinutes = item.startMinutes,
                  let start = DayKey.date(dayKey: item.date, minutes: startMinutes, calendar: calendar)
            else { return nil }
            // 終わりの時刻がない予定(例: 起きる 6:30)は、15分の予定として書き出す
            let end = item.endMinutes.flatMap { DayKey.date(dayKey: item.date, minutes: $0, calendar: calendar) }
                ?? start.addingTimeInterval(15 * 60)
            let title = (item.done ? "✓ " : "") + "\(item.title)(\(item.subject))"
            return CalendarEventDraft(itemId: item.id, title: title, start: start, end: end, notes: notes(for: item))
        }
    }

    /// カレンダーのメモ欄に入れる文(メモ・手順・注意)。何も無ければ nil
    static func notes(for item: PlanItem) -> String? {
        var parts: [String] = []
        if let note = item.note, !note.isEmpty { parts.append(note) }
        if !item.steps.isEmpty {
            parts.append("手順\n" + item.steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))
        }
        if !item.cautions.isEmpty {
            parts.append("注意\n" + item.cautions.map { "・\($0)" }.joined(separator: "\n"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
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
