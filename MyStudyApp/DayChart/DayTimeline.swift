import Foundation

/// 円グラフの1区間(0時からの分数で表す)
struct TimelineSegment: Identifiable, Equatable {
    let id: UUID
    /// 0時からの分数(0〜1440)
    let startMinute: Double
    let endMinute: Double
    let title: String
    let subject: String
    /// 何本目の輪に描くか(0 = いちばん外側)。タイマーを同時に動かしたときだけ 1 以上になる
    let lane: Int

    var minutes: Int { Int((endMinute - startMinute).rounded()) }
}

/// 科目ごとの合計
struct SubjectTotal: Equatable, Identifiable {
    let subject: String
    let minutes: Int
    /// 勉強時間の合計に入れるか(生活の時間は false)
    var isStudy: Bool = true
    var id: String { subject }
}

// 1日ぶんのタイマーの記録から、円グラフに描く形を作る計算。
// (画面の部品から分けて、テストできるようにしている)
struct DayTimeline: Equatable {
    var segments: [TimelineSegment]
    /// 輪の数(同時に動いていたタイマーの数の最大)
    var laneCount: Int
    /// 勉強した合計(分)。同時に動かしていた時間は1回だけ数える。生活の時間(食事・移動など)は入れない
    var totalMinutes: Int
    var subjectTotals: [SubjectTotal]

    static let empty = DayTimeline(segments: [], laneCount: 1, totalMinutes: 0, subjectTotals: [])

    static func build(sessions: [StudySession], dayKey: String, calendar: Calendar = DayKey.gregorian()) -> DayTimeline {
        guard let dayStart = DayKey.date(dayKey: dayKey, minutes: 0, calendar: calendar),
              let dayEnd = DayKey.date(dayKey: DayKey.adding(1, to: dayKey, calendar: calendar), minutes: 0, calendar: calendar)
        else { return .empty }

        // その日にかかっている区間だけを、0時〜24時の中に切りとる(日付をまたいだ区間も、その日の分だけ)
        var pieces: [(id: UUID, start: Double, end: Double, title: String, subject: String)] = []
        var seen = Set<UUID>()
        for session in sessions where !seen.contains(session.id) {
            seen.insert(session.id)
            let start = max(session.startedAt, dayStart)
            let end = min(session.endedAt, dayEnd)
            guard end > start else { continue }
            let startMinute = start.timeIntervalSince(dayStart) / 60
            let endMinute = end.timeIntervalSince(dayStart) / 60
            guard endMinute - startMinute >= 0.5 else { continue }   // 30秒未満は描かない
            pieces.append((session.id, startMinute, endMinute, session.title, session.subject))
        }
        pieces.sort { ($0.start, $0.end) < ($1.start, $1.end) }

        // 重なっている区間は、別の輪に置く(空いているいちばん外側の輪)
        var laneEnds: [Double] = []
        var segments: [TimelineSegment] = []
        for piece in pieces {
            let lane: Int
            if let free = laneEnds.firstIndex(where: { $0 <= piece.start }) {
                lane = free
                laneEnds[free] = piece.end
            } else {
                lane = laneEnds.count
                laneEnds.append(piece.end)
            }
            segments.append(TimelineSegment(id: piece.id, startMinute: piece.start, endMinute: piece.end,
                                            title: piece.title, subject: piece.subject, lane: lane))
        }

        // 合計: 重なりは1回だけ数える。
        // 食事・移動などの生活の時間は、円グラフと一覧には描くが、勉強時間の合計には入れない
        var total = 0.0
        var currentStart: Double?
        var currentEnd = 0.0
        for piece in pieces where StudyKind.isStudy(subject: piece.subject, title: piece.title) {
            if let start = currentStart, piece.start <= currentEnd {
                currentEnd = max(currentEnd, piece.end)
                currentStart = start
            } else {
                if let start = currentStart { total += currentEnd - start }
                currentStart = piece.start
                currentEnd = piece.end
            }
        }
        if let start = currentStart { total += currentEnd - start }

        // 科目ごとの合計(多い順)
        // 勉強の科目は科目ごとに。生活の時間(「その他」の夕食などもふくむ)は、最後に「生活」1行にまとめる
        var bySubject: [String: Double] = [:]
        var lifeMinutes = 0.0
        for piece in pieces {
            if StudyKind.isStudy(subject: piece.subject, title: piece.title) {
                bySubject[piece.subject, default: 0] += piece.end - piece.start
            } else {
                lifeMinutes += piece.end - piece.start
            }
        }
        var subjectTotals = bySubject
            .map { SubjectTotal(subject: $0.key, minutes: Int($0.value.rounded())) }
            .filter { $0.minutes > 0 }
            .sorted { $0.minutes != $1.minutes ? $0.minutes > $1.minutes : $0.subject < $1.subject }
        if Int(lifeMinutes.rounded()) > 0 {
            subjectTotals.append(SubjectTotal(subject: "生活", minutes: Int(lifeMinutes.rounded()), isStudy: false))
        }

        return DayTimeline(segments: segments, laneCount: max(1, laneEnds.count),
                           totalMinutes: Int(total.rounded()), subjectTotals: subjectTotals)
    }

    /// 0時からの分数 → "16:30"
    static func clock(_ minute: Double) -> String {
        let m = Int(minute.rounded())
        return String(format: "%d:%02d", m / 60, m % 60)
    }
}

/// タイマーの記録を、iPhone の中にずっと残しておく場所(グラフ用。サーバーに送ったあとも消さない)
@MainActor
final class SessionHistory {
    static let shared = SessionHistory()

    private(set) var sessions: [StudySession] = []
    private let fileURL: URL?
    /// これより古い記録は、ファイルが大きくなりすぎないように捨てる
    private let keepDays: Int

    init(fileURL: URL? = SessionHistory.defaultFileURL, keepDays: Int = 400) {
        self.fileURL = fileURL
        self.keepDays = keepDays
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([StudySession].self, from: data) {
            sessions = saved
        }
    }

    nonisolated static var defaultFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("session-history.json")
    }

    nonisolated static func clearSaved() {
        if let url = defaultFileURL { try? FileManager.default.removeItem(at: url) }
    }

    func append(_ session: StudySession, now: Date = Date()) {
        guard !sessions.contains(where: { $0.id == session.id }) else { return }
        sessions.append(session)
        let limit = now.addingTimeInterval(-Double(keepDays) * 24 * 3600)
        sessions.removeAll { $0.endedAt < limit }
        save()
    }

    /// その日にかかっている記録
    func sessions(on dayKey: String, calendar: Calendar = DayKey.gregorian()) -> [StudySession] {
        guard let start = DayKey.date(dayKey: dayKey, minutes: 0, calendar: calendar),
              let end = DayKey.date(dayKey: DayKey.adding(1, to: dayKey, calendar: calendar), minutes: 0, calendar: calendar)
        else { return [] }
        return sessions.filter { $0.endedAt > start && $0.startedAt < end }
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(sessions) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
