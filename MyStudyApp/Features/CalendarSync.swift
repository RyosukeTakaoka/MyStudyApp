import EventKit
import Foundation

/// アプリに表示する、カレンダーの予定1件
struct CalendarEventInfo: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarTitle: String
}

// iPhone のカレンダー(純正カレンダー)との連携係。
//   ・書き出し: 予定ブロックを「MyStudy」という専用カレンダーに書き出す
//   ・読みこみ: ほかのカレンダー(学校・Google カレンダーなど)の予定を、アプリに表示する
//
// Google カレンダーは、iPhone の「設定 → カレンダー → アカウント」に Google アカウントを
// 追加しておけば、ここから一緒に読めます。
@MainActor
enum CalendarSync {
    /// カレンダーの窓口。アプリ全体で1つを使い回す
    private static let store = EKEventStore()
    private static let calendarIdKey = "calendar.mystudyCalendarId"
    private static let calendarTitle = "MyStudy"

    /// カレンダーの読み書きが許可されているか
    static var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// 許可を求める(初回だけ iPhone の確認画面が出る)。許可されたら true
    static func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    // MARK: - 書き出し

    /// 予定ブロックと睡眠を「MyStudy」カレンダーに書き出す。
    /// from〜to の期間について、カレンダー側をアプリの予定と同じ状態にそろえる。
    /// sleeps が nil(睡眠の予定を読めなかった)のときは、カレンダーの「睡眠」には手をつけない
    static func export(items: [PlanItem], sleeps: [SleepPlan]? = nil, from: String, to: String) {
        guard isAuthorized, let calendar = mystudyCalendar(),
              let start = DayKey.date(dayKey: from, minutes: 0),
              let end = DayKey.date(dayKey: DayKey.adding(1, to: to), minutes: 0)
        else { return }

        // 期間内の、MyStudy カレンダーの予定を読む
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [calendar])
        let allEvents = store.events(matching: predicate)
        // 睡眠(URL が mystudy://sleep/…)と、それ以外(予定)に分けて、別々にくらべる
        let sleepEvents = allEvents.filter { CalendarSyncPlan.sleepId(from: $0.url) != nil }
        let events = allEvents.filter { CalendarSyncPlan.sleepId(from: $0.url) == nil }
        let existing = events.map { event in
            ExistingCalendarEvent(
                key: event.calendarItemIdentifier,
                itemId: CalendarSyncPlan.itemId(from: event.url),
                title: event.title ?? "",
                start: event.startDate,
                end: event.endDate,
                notes: event.notes
            )
        }
        let byKey = Dictionary(allEvents.map { ($0.calendarItemIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
        let changes = CalendarSyncPlan.diff(drafts: CalendarSyncPlan.drafts(items: items), existing: existing)

        // 睡眠: 読めたときだけ、カレンダーの「睡眠」をそろえる
        var sleepChanges = CalendarSyncPlan.Changes()
        if let sleeps {
            let existingSleeps = sleepEvents.map { event in
                ExistingCalendarEvent(
                    key: event.calendarItemIdentifier,
                    itemId: CalendarSyncPlan.sleepId(from: event.url),
                    title: event.title ?? "",
                    start: event.startDate,
                    end: event.endDate,
                    notes: event.notes
                )
            }
            sleepChanges = CalendarSyncPlan.diff(drafts: CalendarSyncPlan.sleepDrafts(sleeps), existing: existingSleeps)
        }

        do {
            for draft in changes.create {
                let event = EKEvent(eventStore: store)
                event.calendar = calendar
                apply(draft, to: event)
                try store.save(event, span: .thisEvent, commit: false)
            }
            for draft in sleepChanges.create {
                let event = EKEvent(eventStore: store)
                event.calendar = calendar
                apply(draft, to: event, url: CalendarSyncPlan.sleepURL(for: draft.itemId))
                try store.save(event, span: .thisEvent, commit: false)
            }
            for (key, draft) in sleepChanges.update {
                guard let event = byKey[key] else { continue }
                apply(draft, to: event, url: CalendarSyncPlan.sleepURL(for: draft.itemId))
                try store.save(event, span: .thisEvent, commit: false)
            }
            for key in sleepChanges.delete {
                guard let event = byKey[key] else { continue }
                try store.remove(event, span: .thisEvent, commit: false)
            }
            for (key, draft) in changes.update {
                guard let event = byKey[key] else { continue }
                apply(draft, to: event)
                try store.save(event, span: .thisEvent, commit: false)
            }
            for key in changes.delete {
                guard let event = byKey[key] else { continue }
                try store.remove(event, span: .thisEvent, commit: false)
            }
            // まとめて保存する
            try store.commit()
        } catch {
            store.reset()
            print("カレンダーへの書き出しに失敗: \(error)")
        }
    }

    private static func apply(_ draft: CalendarEventDraft, to event: EKEvent, url: URL? = nil) {
        event.title = draft.title
        event.startDate = draft.start
        event.endDate = draft.end
        event.notes = draft.notes
        event.url = url ?? CalendarSyncPlan.url(for: draft.itemId)
    }

    /// 「MyStudy」カレンダーを探す。無ければ作る
    private static func mystudyCalendar() -> EKCalendar? {
        if let id = UserDefaults.standard.string(forKey: calendarIdKey),
           let calendar = store.calendar(withIdentifier: id) {
            return calendar
        }
        if let found = store.calendars(for: .event).first(where: { $0.title == calendarTitle && $0.allowsContentModifications }) {
            UserDefaults.standard.set(found.calendarIdentifier, forKey: calendarIdKey)
            return found
        }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = calendarTitle
        calendar.cgColor = CGColor(red: 0.18, green: 0.42, blue: 0.66, alpha: 1)
        // iCloud があればそこに作る(ほかの端末の純正カレンダーにも出る)。無ければこの iPhone の中に作る
        calendar.source = store.sources.first { $0.sourceType == .calDAV && $0.title == "iCloud" }
            ?? store.defaultCalendarForNewEvents?.source
            ?? store.sources.first { $0.sourceType == .local }
        do {
            try store.saveCalendar(calendar, commit: true)
            UserDefaults.standard.set(calendar.calendarIdentifier, forKey: calendarIdKey)
            return calendar
        } catch {
            print("MyStudy カレンダーを作れませんでした: \(error)")
            return nil
        }
    }

    // MARK: - 読みこみ

    /// その日の、ほかのカレンダーの予定(MyStudy カレンダーは除く)
    static func events(on dayKey: String) -> [CalendarEventInfo] {
        guard isAuthorized,
              let start = DayKey.date(dayKey: dayKey, minutes: 0),
              let end = DayKey.date(dayKey: DayKey.adding(1, to: dayKey), minutes: 0)
        else { return [] }
        let ownId = UserDefaults.standard.string(forKey: calendarIdKey)
        let calendars = store.calendars(for: .event).filter { $0.calendarIdentifier != ownId }
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate)
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
            .map { event in
                CalendarEventInfo(
                    id: event.calendarItemIdentifier + "\(event.startDate.timeIntervalSince1970)",
                    title: event.title ?? "(タイトルなし)",
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    calendarTitle: event.calendar.title
                )
            }
    }
}
