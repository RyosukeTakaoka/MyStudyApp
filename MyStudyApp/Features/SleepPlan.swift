import Foundation

/// 睡眠の予定(sleep_plans テーブルの1行)。
/// アプリの画面には出さず、iPhone のカレンダー(MyStudy)に「睡眠」として書き出すだけに使う。
struct SleepPlan: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    /// その夜の日付("2026-11-18")
    var night: String
    /// 寝る時刻
    var startAt: Date
    /// 起きる時刻
    var endAt: Date
    var note: String?
    /// 実際に寝た時間(分)。アプリのタイマーで測った区間から、サーバーが計算する
    var actualMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case id, night, note
        case startAt = "start_at"
        case endAt = "end_at"
        case actualMinutes = "actual_minutes"
    }

    init(id: UUID, night: String, startAt: Date, endAt: Date, note: String?, actualMinutes: Int? = nil) {
        self.id = id
        self.night = night
        self.startAt = startAt
        self.endAt = endAt
        self.note = note
        self.actualMinutes = actualMinutes
    }

    /// サーバーから読んだもの・端末に保存したものを読む(日時は文字でも数でも読めるようにする)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        night = try c.decode(String.self, forKey: .night)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        startAt = try Self.decodeDate(c, .startAt)
        endAt = try Self.decodeDate(c, .endAt)
        actualMinutes = try? c.decodeIfPresent(Int.self, forKey: .actualMinutes)
    }

    /// 端末に保存するときは、日時を "…Z" の文字にする(読み直しても同じになるように)
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let style = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        try c.encode(id, forKey: .id)
        try c.encode(night, forKey: .night)
        try c.encode(startAt.formatted(style), forKey: .startAt)
        try c.encode(endAt.formatted(style), forKey: .endAt)
        try c.encodeIfPresent(note, forKey: .note)
        try c.encodeIfPresent(actualMinutes, forKey: .actualMinutes)
    }

    /// 「今日」の予定の一覧に出すための形(ほかの予定と同じ1行)。
    /// その夜の日付の、寝る時刻の予定(終わりの時刻なし)。0時すぎに寝る日は、その日の最後(23:59)に並べる。
    /// source = "sleep" の印を付ける(チェック・編集・削除はできない。長押しでタイマーは使える)
    func asPlanItem(calendar: Calendar = DayKey.gregorian()) -> PlanItem {
        let startKey = DayKey.today(now: startAt, calendar: calendar)
        let startMinutes = startKey == night ? DayKey.minutesOfDay(startAt, calendar: calendar) : 23 * 60 + 59
        let wake = TimeOfDay.text(DayKey.minutesOfDay(endAt, calendar: calendar))
        let bed = TimeOfDay.text(DayKey.minutesOfDay(startAt, calendar: calendar))
        let length = Int(endAt.timeIntervalSince(startAt) / 60)
        var noteParts = ["\(bed) に寝て、\(wake) に起きる(\(NowNext.durationText(length)))"]
        if let note, !note.isEmpty { noteParts.append(note) }
        return PlanItem(
            id: id, date: night, kind: "block",
            startTime: String(format: "%02d:%02d:00", startMinutes / 60, startMinutes % 60), endTime: nil,
            title: "睡眠", subject: "生活", sortOrder: 0, source: PlanItem.sleepSource,
            done: false, doneAt: nil, actualMinutes: actualMinutes, note: noteParts.joined(separator: "\n")
        )
    }

    private static func decodeDate(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> Date {
        if let text = try? c.decode(String.self, forKey: key) {
            return try StudySession.parseDate(text)
        }
        return try c.decode(Date.self, forKey: key)
    }
}

/// 睡眠の予定を、端末にも取っておく場所(電波が無いときも、カレンダーの「睡眠」を消さないため)
enum SleepCache {
    static var fileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("sleep-plans.json")
    }

    static func load(from url: URL? = fileURL) -> [SleepPlan]? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([SleepPlan].self, from: data)
    }

    static func save(_ plans: [SleepPlan], to url: URL? = fileURL) {
        guard let url, let data = try? JSONEncoder().encode(plans) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// ログアウトしたときに消す
    static func clearSaved() {
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
    }
}
