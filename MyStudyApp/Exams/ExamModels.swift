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
    /// アプリで測った勉強時間の合計(分。鑑定士の勉強だけ)
    var studyMinutes: Double
    var nextExam: ExamResult?
    /// 月ごとの配分(Claude が決める。無ければ空)
    var monthPlans: [MonthPlan] = []
    /// 今月(1日の 0:00 から)の勉強時間(分。鑑定士の勉強だけ)
    var minutesThisMonth: Double = 0

    enum CodingKeys: String, CodingKey {
        case target, studyMinutes, nextExam, monthPlans, minutesThisMonth
    }

    init(target: StudyTarget, studyMinutes: Double, nextExam: ExamResult?,
         monthPlans: [MonthPlan] = [], minutesThisMonth: Double = 0) {
        self.target = target
        self.studyMinutes = studyMinutes
        self.nextExam = nextExam
        self.monthPlans = monthPlans
        self.minutesThisMonth = minutesThisMonth
    }

    /// 前の版で端末に取っておいたもの(配分が無い)も読めるようにする
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        target = try c.decode(StudyTarget.self, forKey: .target)
        studyMinutes = try c.decode(Double.self, forKey: .studyMinutes)
        nextExam = try c.decodeIfPresent(ExamResult.self, forKey: .nextExam)
        monthPlans = (try? c.decodeIfPresent([MonthPlan].self, forKey: .monthPlans)) ?? []
        minutesThisMonth = (try? c.decodeIfPresent(Double.self, forKey: .minutesThisMonth)) ?? 0
    }

    /// その日をふくむ月の1日("2026-11-01")
    static func monthStart(of dayKey: String) -> String { String(dayKey.prefix(7)) + "-01" }

    /// 次の月の1日
    static func nextMonthStart(after monthKey: String) -> String {
        let parts = monthKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count >= 2 else { return monthKey }
        var year = parts[0], month = parts[1] + 1
        if month > 12 { month = 1; year += 1 }
        return String(format: "%04d-%02d-01", year, month)
    }

    /// 月ごとの割りあて(今月から、目標の日の前の月まで)。配分が1つも無ければ nil。
    /// 配分のある月はその時間、無い月は「残りの時間を等分」
    func monthAllotments(today: String) -> [MonthAllotment]? {
        guard !monthPlans.isEmpty, let targetDate = target.targetDate, targetDate > today else { return nil }
        var months: [String] = []
        var month = Self.monthStart(of: today)
        while month < targetDate && months.count < 36 {
            months.append(month)
            month = Self.nextMonthStart(after: month)
        }
        guard !months.isEmpty else { return nil }
        let planned = Dictionary(monthPlans.map { ($0.month, $0.plannedHours) }, uniquingKeysWith: { a, _ in a })
        let base = hoursAtMonthStart
        let known = months.compactMap { planned[$0] }.reduce(0, +)
        let unknownCount = months.filter { planned[$0] == nil }.count
        let share = unknownCount > 0 ? max(Double(target.totalHoursGoal) - base - known, 0) / Double(unknownCount) : 0
        return months.map { MonthAllotment(month: $0, hours: planned[$0] ?? share, isPlanned: planned[$0] != nil) }
    }

    /// 今月の1日の時点の累計
    var hoursAtMonthStart: Double { max(totalHours - minutesThisMonth / 60, 0) }

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

    /// 月の目盛り: 今日から目標の日まで同じペースで進んだら、各月の始まり(1日)に何時間になっているか。
    /// 例: 今日 11/23・目標 2027/8/1 → 12月, 1月, …, 8月 の目盛り(8月は目標の時間ちょうど)
    func monthTicks(today: String) -> [MonthTick] {
        // 月ごとの配分があれば、その配分を積み上げた位置(今月の1日の累計 + 各月の割りあて)
        if let allotments = monthAllotments(today: today) {
            var cumulative = hoursAtMonthStart
            return allotments.map { allotment in
                cumulative += allotment.hours
                let next = Self.nextMonthStart(after: allotment.month)
                let monthNumber = Int(next.split(separator: "-")[1]) ?? 0
                return MonthTick(month: monthNumber, dayKey: next, hours: cumulative)
            }
        }
        guard let targetDate = target.targetDate, targetDate > today,
              let start = DayKey.date(dayKey: today, minutes: 0),
              let end = DayKey.date(dayKey: targetDate, minutes: 0)
        else { return [] }
        let goal = Double(target.totalHoursGoal)
        let now = totalHours
        guard goal > now else { return [] }
        let span = end.timeIntervalSince(start)
        var ticks: [MonthTick] = []
        let parts = today.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return [] }
        var year = parts[0], month = parts[1]
        while true {
            month += 1
            if month > 12 { month = 1; year += 1 }
            let key = String(format: "%04d-%02d-01", year, month)
            guard key <= targetDate, let date = DayKey.date(dayKey: key, minutes: 0) else { break }
            let hours = now + (goal - now) * date.timeIntervalSince(start) / span
            ticks.append(MonthTick(month: month, dayKey: key, hours: hours))
            if ticks.count > 36 { break }   // 念のため(3年分まで)
        }
        return ticks
    }

    /// 目標の日まで、1か月あたり何時間ずつ必要か
    func hoursPerMonth(today: String) -> Double? {
        guard let days = daysLeft(from: today), days > 0 else { return nil }
        let remaining = Double(target.totalHoursGoal) - totalHours
        guard remaining > 0 else { return 0 }
        return remaining / (Double(days) / 30.44)
    }

    /// 目標の日まで、1日あたり何時間ずつ必要か(今日もふくめて数える)
    func hoursPerDay(today: String) -> Double? {
        // 月ごとの配分があれば「今月あと ÷ 今月の残りの日数(今日をふくむ)」
        if let month = hoursLeftThisMonth(today: today), monthAllotments(today: today) != nil {
            guard let a = DayKey.date(dayKey: today, minutes: 12 * 60),
                  let b = DayKey.date(dayKey: month.until, minutes: 12 * 60) else { return nil }
            let days = max(Int((b.timeIntervalSince(a) / 86400).rounded()), 1)
            return month.hours / Double(days)
        }
        guard let days = daysLeft(from: today), days > 0 else { return nil }
        let remaining = Double(target.totalHoursGoal) - totalHours
        guard remaining > 0 else { return 0 }
        return remaining / Double(days)
    }

    /// 今月あと何時間か(次の月の目盛り = 来月1日 までに、同じペースなら何時間ふやすか)。
    /// 目盛りが無いときは nil
    func hoursLeftThisMonth(today: String) -> (hours: Double, until: String)? {
        if let allotments = monthAllotments(today: today), let this = allotments.first {
            return (max(this.hours - minutesThisMonth / 60, 0), Self.nextMonthStart(after: this.month))
        }
        guard let first = monthTicks(today: today).first else { return nil }
        return (max(first.hours - totalHours, 0), first.dayKey)
    }

    /// これからの答練のうち、いちばん近いもの
    static func nextExam(in exams: [ExamResult], today: String) -> ExamResult? {
        exams.filter { $0.isUpcoming && $0.examDate >= today }
            .min { ($0.examDate, $0.startTime ?? "") < ($1.examDate, $1.startTime ?? "") }
    }
}

/// 累計時間のバーの月の目盛り
struct MonthTick: Equatable, Identifiable, Sendable {
    var month: Int          // 12, 1, 2, …
    var dayKey: String      // その月の1日
    var hours: Double       // 同じペースなら、その日に何時間になっているか
    var id: String { dayKey }
}

/// 月ごとの配分(study_month_plans テーブル。Claude が書く)
struct MonthPlan: Codable, Equatable, Sendable {
    var month: String          // その月の1日("2026-12-01")
    var plannedHours: Double

    enum CodingKeys: String, CodingKey {
        case month
        case plannedHours = "planned_hours"
    }

    init(month: String, plannedHours: Double) {
        self.month = month
        self.plannedHours = plannedHours
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        month = try c.decode(String.self, forKey: .month)
        if let v = try? c.decode(Double.self, forKey: .plannedHours) {
            plannedHours = v
        } else {
            plannedHours = Double(try c.decode(String.self, forKey: .plannedHours)) ?? 0
        }
    }
}

/// 1か月分の割りあて
struct MonthAllotment: Equatable, Sendable {
    var month: String
    var hours: Double
    /// Claude が決めた配分か(false なら残りを等分した値)
    var isPlanned: Bool
}
