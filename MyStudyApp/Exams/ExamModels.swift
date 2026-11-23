import Foundation

/// 答練(模試)1回分。exam_results テーブルの1行。
/// 点数が無い(nil)ものは「これから受ける答練」として扱う
struct ExamResult: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var examDate: String          // "2026-11-29"
    var startTime: String?        // "09:00:00"
    var subject: String
    var title: String             // 例 応用答練 第4回
    var score: Double?
    var fullScore: Double?
    var average: Double?
    var rank: Int?
    var examinees: Int?
    var goodPoints: String?       // 良かった点
    var missedPoints: String?     // 論点漏れ・できなかった点
    var nextActions: String?      // 次にやること
    var note: String?
    var source: String = "app"

    enum CodingKeys: String, CodingKey {
        case id, subject, title, score, average, rank, examinees, note, source
        case examDate = "exam_date"
        case startTime = "start_time"
        case fullScore = "full_score"
        case goodPoints = "good_points"
        case missedPoints = "missed_points"
        case nextActions = "next_actions"
    }

    init(id: UUID = UUID(), examDate: String, startTime: String? = nil, subject: String, title: String,
         score: Double? = nil, fullScore: Double? = nil, average: Double? = nil, rank: Int? = nil, examinees: Int? = nil,
         goodPoints: String? = nil, missedPoints: String? = nil, nextActions: String? = nil, note: String? = nil,
         source: String = "app") {
        self.id = id
        self.examDate = examDate
        self.startTime = startTime
        self.subject = subject
        self.title = title
        self.score = score
        self.fullScore = fullScore
        self.average = average
        self.rank = rank
        self.examinees = examinees
        self.goodPoints = goodPoints
        self.missedPoints = missedPoints
        self.nextActions = nextActions
        self.note = note
        self.source = source
    }

    /// サーバーの数(numeric)は文字で届くこともあるので、数でも文字でも読めるようにする
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        examDate = try c.decode(String.self, forKey: .examDate)
        startTime = try c.decodeIfPresent(String.self, forKey: .startTime)
        subject = try c.decodeIfPresent(String.self, forKey: .subject) ?? "その他"
        title = try c.decode(String.self, forKey: .title)
        score = Self.number(c, .score)
        fullScore = Self.number(c, .fullScore)
        average = Self.number(c, .average)
        rank = try? c.decodeIfPresent(Int.self, forKey: .rank)
        examinees = try? c.decodeIfPresent(Int.self, forKey: .examinees)
        goodPoints = try c.decodeIfPresent(String.self, forKey: .goodPoints)
        missedPoints = try c.decodeIfPresent(String.self, forKey: .missedPoints)
        nextActions = try c.decodeIfPresent(String.self, forKey: .nextActions)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        source = (try? c.decodeIfPresent(String.self, forKey: .source)) ?? "app"
    }

    /// 送るときは、空の項目も null として送る(書きかえで消した項目を、サーバーでも消すため)
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(examDate, forKey: .examDate)
        try c.encode(startTime, forKey: .startTime)
        try c.encode(subject, forKey: .subject)
        try c.encode(title, forKey: .title)
        try c.encode(score, forKey: .score)
        try c.encode(fullScore, forKey: .fullScore)
        try c.encode(average, forKey: .average)
        try c.encode(rank, forKey: .rank)
        try c.encode(examinees, forKey: .examinees)
        try c.encode(goodPoints, forKey: .goodPoints)
        try c.encode(missedPoints, forKey: .missedPoints)
        try c.encode(nextActions, forKey: .nextActions)
        try c.encode(note, forKey: .note)
        try c.encode(source, forKey: .source)
    }

    private static func number(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
        if let value = try? c.decodeIfPresent(Double.self, forKey: key) { return value }
        if let text = try? c.decodeIfPresent(String.self, forKey: key) { return Double(text) }
        return nil
    }

    /// まだ受けていない(点数が無い)
    var isUpcoming: Bool { score == nil }

    /// 満点に対する割合(%)。満点が無ければ点数そのもの
    var scoreForChart: Double? {
        guard let score else { return nil }
        if let fullScore, fullScore > 0 { return score / fullScore * 100 }
        return score
    }

    /// 例 "11/29(日) 9:00"
    var whenText: String {
        var text = DayKey.shortText(examDate)
        if let minutes = TimeOfDay.minutes(from: startTime) { text += " " + TimeOfDay.text(minutes) }
        return text
    }

    /// 例 "62点 / 平均55点 ・ 3位 / 120人"
    var scoreText: String {
        func fmt(_ v: Double) -> String { v.rounded() == v ? String(Int(v)) : String(format: "%.1f", v) }
        var parts: [String] = []
        if let score {
            var s = "\(fmt(score))点"
            if let fullScore { s += "/\(fmt(fullScore))" }
            parts.append(s)
        }
        if let average { parts.append("平均\(fmt(average))点") }
        if let rank {
            parts.append(examinees.map { "\(rank)位/\($0)人" } ?? "\(rank)位")
        }
        return parts.joined(separator: " ・ ")
    }
}

/// 長期の目標(study_targets テーブル。Claude が書く)
struct StudyTarget: Codable, Equatable, Sendable {
    var targetName: String
    var targetDate: String?
    var totalHoursGoal: Int
    var hoursBeforeApp: Double

    enum CodingKeys: String, CodingKey {
        case targetName = "target_name"
        case targetDate = "target_date"
        case totalHoursGoal = "total_hours_goal"
        case hoursBeforeApp = "hours_before_app"
    }

    init(targetName: String, targetDate: String?, totalHoursGoal: Int, hoursBeforeApp: Double) {
        self.targetName = targetName
        self.targetDate = targetDate
        self.totalHoursGoal = totalHoursGoal
        self.hoursBeforeApp = hoursBeforeApp
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        targetName = try c.decodeIfPresent(String.self, forKey: .targetName) ?? "試験"
        targetDate = try c.decodeIfPresent(String.self, forKey: .targetDate)
        totalHoursGoal = (try? c.decodeIfPresent(Int.self, forKey: .totalHoursGoal)) ?? 3000
        if let v = try? c.decodeIfPresent(Double.self, forKey: .hoursBeforeApp) {
            hoursBeforeApp = v
        } else if let text = try? c.decodeIfPresent(String.self, forKey: .hoursBeforeApp), let v = Double(text) {
            hoursBeforeApp = v
        } else {
            hoursBeforeApp = 0
        }
    }

    static let fallback = StudyTarget(targetName: "論文式試験", targetDate: nil, totalHoursGoal: 3000, hoursBeforeApp: 0)
}

/// 「今日」の上の帯に出す中身(端末にも取っておく)
struct TargetBandData: Codable, Equatable, Sendable {
    var target: StudyTarget
    /// アプリで測った勉強時間の合計(分。生活の時間はのぞく)
    var studyMinutes: Double
    var nextExam: ExamResult?

    /// その日から目標の日まで、あと何日か(目標の日が無ければ nil)
    func daysLeft(from today: String) -> Int? {
        guard let targetDate = target.targetDate,
              let a = DayKey.date(dayKey: today, minutes: 12 * 60),
              let b = DayKey.date(dayKey: targetDate, minutes: 12 * 60)
        else { return nil }
        return Int((b.timeIntervalSince(a) / 86400).rounded())
    }

    /// 累計時間(アプリを使う前の分 + アプリで測った分)
    var totalHours: Double { target.hoursBeforeApp + studyMinutes / 60 }

    /// これからの答練のうち、いちばん近いもの
    static func nextExam(in exams: [ExamResult], today: String) -> ExamResult? {
        exams.filter { $0.isUpcoming && $0.examDate >= today }
            .min { ($0.examDate, $0.startTime ?? "") < ($1.examDate, $1.startTime ?? "") }
    }
}
