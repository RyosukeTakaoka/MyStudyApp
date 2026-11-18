import Foundation

/// アプリ → ウィジェットに渡すデータ。共有フォルダに JSON で置きます。
/// 今日と明日の2日分を入れておく(夜0時をまたいでも、ウィジェットが明日の予定を出せるように)。
struct WidgetSnapshot: Codable, Equatable {
    struct Day: Codable, Equatable {
        var goal: String?
        var items: [PlanItem]
        /// iPhone のカレンダー(学校の時間割・Google など)の、時間のある予定。
        /// 「今」の予定が無い時間に、ウィジェットの「今」に出す(例: 授業の「化学」)
        var events: [WidgetCalendarEvent] = []
    }

    /// 日付キー("2026-11-13")ごとのデータ
    var days: [String: Day]

    static let empty = WidgetSnapshot(days: [:])

    func day(_ key: String) -> Day {
        days[key] ?? Day(goal: nil, items: [])
    }
}

extension WidgetSnapshot.Day {
    /// 前の版で保存したデータ(events が無い)も読めるようにする
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        goal = try c.decodeIfPresent(String.self, forKey: .goal)
        items = try c.decode([PlanItem].self, forKey: .items)
        events = try c.decodeIfPresent([WidgetCalendarEvent].self, forKey: .events) ?? []
    }
}

/// カレンダーの予定1件(ウィジェットに渡す分だけ)
struct WidgetCalendarEvent: Codable, Equatable, Sendable {
    var title: String
    var start: Date
    var end: Date

    /// その時刻に行われている予定(重なっていれば、あとから始まったほう)。無ければ nil
    static func current(in events: [WidgetCalendarEvent], at date: Date) -> WidgetCalendarEvent? {
        events.filter { $0.start <= date && date < $0.end }.max { $0.start < $1.start }
    }
}

/// ウィジェットでチェックした記録。アプリが次に開いたときに取りこんで、サーバーへ送ります。
struct PendingToggle: Codable, Equatable {
    var itemId: UUID
    var done: Bool
    var doneAt: Date?
}

/// 共有フォルダの読み書き。アプリとウィジェットの両方から使います。
/// (dir を引数にしているのは、テストで別のフォルダを使えるようにするため)
enum SharedStore {
    private static let snapshotFile = "widget-snapshot.json"
    private static let togglesFile = "widget-toggles.json"

    static func readSnapshot(in dir: URL? = AppGroup.containerURL) -> WidgetSnapshot {
        read(WidgetSnapshot.self, file: snapshotFile, in: dir) ?? .empty
    }

    static func writeSnapshot(_ snapshot: WidgetSnapshot, in dir: URL? = AppGroup.containerURL) {
        write(snapshot, file: snapshotFile, in: dir)
    }

    /// ウィジェットのチェックボタンが押されたとき: 表示用データを書きかえ、記録を残す
    @discardableResult
    static func toggleFromWidget(itemId: UUID, now: Date, in dir: URL? = AppGroup.containerURL) -> Bool {
        var snapshot = readSnapshot(in: dir)
        for (key, var day) in snapshot.days {
            guard let index = day.items.firstIndex(where: { $0.id == itemId }) else { continue }
            day.items[index].done.toggle()
            day.items[index].doneAt = day.items[index].done ? now : nil
            snapshot.days[key] = day
            writeSnapshot(snapshot, in: dir)

            var toggles = read([PendingToggle].self, file: togglesFile, in: dir) ?? []
            toggles.append(PendingToggle(itemId: itemId, done: day.items[index].done, doneAt: day.items[index].doneAt))
            write(toggles, file: togglesFile, in: dir)
            return true
        }
        return false
    }

    /// ウィジェットでのチェック記録を取り出して、ファイルを空にする(アプリが呼ぶ)
    static func takePendingToggles(in dir: URL? = AppGroup.containerURL) -> [PendingToggle] {
        let toggles = read([PendingToggle].self, file: togglesFile, in: dir) ?? []
        if !toggles.isEmpty, let dir {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(togglesFile))
        }
        return toggles
    }

    // MARK: - 中で使う道具

    private static func read<T: Decodable>(_ type: T.Type, file: String, in dir: URL?) -> T? {
        guard let dir, let data = try? Data(contentsOf: dir.appendingPathComponent(file)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func write<T: Encodable>(_ value: T, file: String, in dir: URL?) {
        guard let dir, let data = try? JSONEncoder().encode(value) else { return }
        // .atomic = 書き終わるまで古いファイルを残す(書きかけを読まれないように)
        try? data.write(to: dir.appendingPathComponent(file), options: .atomic)
    }
}

/// ウィジェットの表示を切りかえるタイミングを決める計算
enum WidgetTimeline {
    /// 今日の予定の開始・終了時刻(=「今 → 次」が変わる瞬間)のうち now より後のもの + 次の 0:00
    static func refreshDates(
        items: [PlanItem],
        dayKey: String,
        now: Date,
        events: [WidgetCalendarEvent] = [],
        calendar: Calendar = DayKey.gregorian(),
        limit: Int = 40
    ) -> [Date] {
        var minutes = Set<Int>()
        for item in items where item.isBlock {
            if let start = item.startMinutes { minutes.insert(start) }
            if let end = item.endMinutes { minutes.insert(end) }
        }
        // カレンダーの予定(授業など)の始まり・終わりでも、「今」の表示を切りかえる
        let eventDates = events.flatMap { [$0.start, $0.end] }
        let dates = Set(minutes.compactMap { DayKey.date(dayKey: dayKey, minutes: $0, calendar: calendar) } + eventDates)
            .filter { $0 > now }
            .sorted()
        let midnight = now.addingTimeInterval(DayKey.secondsUntilNextDay(now: now, calendar: calendar) + 1)
        return Array(dates.filter { $0 < midnight }.prefix(limit)) + [midnight]
    }
}
