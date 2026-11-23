import Foundation

// items テーブルの1行を表す型。
// Codable を付けると、Supabase から届く JSON と自動で相互変換できます。
struct PlanItem: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var date: String          // "2026-11-13" の形
    var kind: String          // "block" = 時間つきの予定 / "task" = 時間なしのやること
    var startTime: String?    // "16:30:00" の形(block のみ)
    var endTime: String?      // "17:30:00" の形(block のみ)
    var title: String
    var subject: String       // 科目(例: 鑑定理論)
    var sortOrder: Int
    var source: String        // "claude" または "app"
    var done: Bool
    var doneAt: Date?
    var actualMinutes: Int?
    var note: String?
    /// 手順(番号つきで表示する)
    var steps: [String] = []
    /// 注意(箇条書きで表示する)
    var cautions: [String] = []
    /// 手で直した実績(分)。入っていれば、タイマーの記録より優先する(nil = タイマーの記録のまま)
    var actualOverride: Int? = nil
    /// つながっている週のやることの題名と、埋める箱の番号(Claude が決める。アプリは表示するだけ)
    var weekGoalTitle: String? = nil
    var weekGoalBoxes: [Int] = []

    // Swift 側の名前(startTime)と、データベース側の列名(start_time)の対応表
    enum CodingKeys: String, CodingKey {
        case id, date, kind, title, subject, source, done, note, steps, cautions
        case startTime = "start_time"
        case endTime = "end_time"
        case sortOrder = "sort_order"
        case doneAt = "done_at"
        case actualMinutes = "actual_minutes"
        case actualOverride = "actual_override"
        case weekGoalTitle = "week_goal_title"
        case weekGoalBoxes = "week_goal_boxes"
    }
}

extension PlanItem {
    /// JSON から読みこむときの手順。
    /// ほとんどは自動と同じだが、done_at だけは「読めなければ nil」にしている。
    /// (日時の形が想定とちがっても、予定の一覧そのものは表示できるようにするため)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(String.self, forKey: .date)
        kind = try c.decode(String.self, forKey: .kind)
        startTime = try c.decodeIfPresent(String.self, forKey: .startTime)
        endTime = try c.decodeIfPresent(String.self, forKey: .endTime)
        title = try c.decode(String.self, forKey: .title)
        subject = try c.decodeIfPresent(String.self, forKey: .subject) ?? "その他"
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "claude"
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        doneAt = (try? c.decodeIfPresent(Date.self, forKey: .doneAt)) ?? nil
        actualMinutes = try c.decodeIfPresent(Int.self, forKey: .actualMinutes)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        // 手順と注意は、無い・読めないときは空にする(古いデータでも表示できるように)
        steps = (try? c.decodeIfPresent([String].self, forKey: .steps)) ?? []
        cautions = (try? c.decodeIfPresent([String].self, forKey: .cautions)) ?? []
        actualOverride = try? c.decodeIfPresent(Int.self, forKey: .actualOverride)
        weekGoalTitle = try? c.decodeIfPresent(String.self, forKey: .weekGoalTitle)
        weekGoalBoxes = ((try? c.decodeIfPresent([Int].self, forKey: .weekGoalBoxes)) ?? nil) ?? []
    }

    /// 予定の行に出す「→ 数学 178・179」(つながりが無ければ nil)
    var weekGoalText: String? {
        guard let title = weekGoalTitle, !title.isEmpty else { return nil }
        return weekGoalBoxes.isEmpty ? title : title + " " + weekGoalBoxes.map(String.init).joined(separator: "・")
    }

    /// 手順か注意があるか
    var hasGuide: Bool { !steps.isEmpty || !cautions.isEmpty }

    /// 時間つきの予定か
    var isBlock: Bool { kind == "block" }

    /// 勉強の予定か(食事・睡眠・移動などは false)。集中モードと自動タイマーは勉強の予定だけで動く
    var isStudy: Bool { StudyKind.isStudy(subject: subject, title: title) }

    /// 開始時刻を「0時からの分数」で表したもの(16:30 → 990)
    var startMinutes: Int? { TimeOfDay.minutes(from: startTime) }

    /// 終了時刻を「0時からの分数」で表したもの。
    /// 終了が開始より前(日付をまたぐ予定)のときは、その日の終わり(24:00)までとして扱う
    var endMinutes: Int? {
        guard let end = TimeOfDay.minutes(from: endTime) else { return nil }
        if let start = startMinutes, end <= start { return 24 * 60 }
        return end
    }

    /// 画面に出す時刻の文字(例: 16:30〜17:30)。task のときは nil
    var timeRangeText: String? {
        guard let start = TimeOfDay.minutes(from: startTime) else { return nil }
        guard let end = TimeOfDay.minutes(from: endTime) else { return TimeOfDay.text(start) }
        return "\(TimeOfDay.text(start))〜\(TimeOfDay.text(end))"
    }

    /// 画面に出す順番に並べる。予定(block)は開始時刻順、やること(task)は sort_order 順。
    static func sortedForDisplay(_ items: [PlanItem]) -> [PlanItem] {
        items.sorted { a, b in
            // 並べる基準を「タプル」にして、左から順にくらべる
            let keyA = (a.isBlock ? 0 : 1, a.startMinutes ?? 0, a.sortOrder, a.title, a.id.uuidString)
            let keyB = (b.isBlock ? 0 : 1, b.startMinutes ?? 0, b.sortOrder, b.title, b.id.uuidString)
            return keyA < keyB
        }
    }
}

// 時刻の文字("16:30:00")と分数(990)を変換する道具
enum TimeOfDay {
    /// "16:30" や "16:30:00" → 990。読めない形なら nil
    static func minutes(from text: String?) -> Int? {
        guard let text else { return nil }
        let parts = text.split(separator: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...24).contains(hour), (0...59).contains(minute)
        else { return nil }
        return hour * 60 + minute
    }

    /// 990 → "16:30"
    static func text(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}

/// 勉強の予定か、生活の予定(食事・睡眠・移動など)かを見分ける決まり。
/// 1. 科目が「生活」などなら → 勉強ではない
/// 2. 科目が勉強の科目(鑑定理論・民法・学校など)なら → 勉強(「夕食を食べながら Anki」も勉強)
/// 3. 科目が「その他」や空のときだけ、題名に「食事・風呂・睡眠・移動…」などがあれば勉強ではない
enum StudyKind {
    /// 勉強ではない科目
    static let nonStudySubjects: Set<String> = ["生活", "食事", "休憩", "睡眠", "移動", "自由", "風呂", "家事"]
    /// 勉強の科目(この科目なら、題名に「夕食」などがあっても勉強)
    static let studySubjects: Set<String> = ["鑑定理論", "行政法規", "民法", "経済", "会計", "学校"]
    /// 科目が「その他」や空のときに見る、生活の言葉
    static let nonStudyWords = [
        "食事", "朝食", "昼食", "夕食", "夜食", "朝ごはん", "昼ごはん", "夜ごはん", "ご飯", "ごはん", "弁当", "お弁当",
        "風呂", "入浴", "シャワー", "睡眠", "就寝", "寝る", "起床", "昼寝", "仮眠",
        "休憩", "移動", "通学", "登校", "下校", "帰宅", "身支度", "支度", "自由時間", "家事",
    ]
    /// 題名にこれがあれば、生活の言葉があっても勉強(例「夕食 + Anki」)
    static let studyWords = ["Anki", "anki", "ANKI", "勉強", "復習", "暗記", "問題", "答練", "演習"]

    static func isStudy(subject: String?, title: String) -> Bool {
        let subject = (subject ?? "").trimmingCharacters(in: .whitespaces)
        if nonStudySubjects.contains(subject) { return false }
        if studySubjects.contains(subject) { return true }
        if studyWords.contains(where: { title.contains($0) }) { return true }
        return !nonStudyWords.contains(where: { title.contains($0) })
    }
}
