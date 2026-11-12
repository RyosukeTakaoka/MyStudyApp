import Foundation

/// 期間の計画(term_plans テーブルの1行)。例: 期末までの週次計画
struct TermPlan: Codable, Equatable, Identifiable, Sendable {
    /// 数字のカード(例: 必要な時間 / 約24時間 / 数学59問…)
    struct Stat: Codable, Equatable, Sendable {
        var label: String
        var value: String
        var detail: String?
    }

    /// 月の流れの1行(例: 〜11/15 / 通常期。…)
    struct Phase: Codable, Equatable, Sendable {
        var range: String
        var color: String?
        var text: String
    }

    let id: UUID
    var title: String
    var startDate: String
    var endDate: String
    var overviewTitle: String?
    var stats: [Stat]
    var overviewNote: String?
    var phases: [Phase]

    enum CodingKeys: String, CodingKey {
        case id, title, stats, phases
        case startDate = "start_date"
        case endDate = "end_date"
        case overviewTitle = "overview_title"
        case overviewNote = "overview_note"
    }
}

/// 1週間の情報(weeks テーブルの1行)
struct WeekPlan: Codable, Equatable, Identifiable, Sendable {
    /// その週の月曜日("2026-11-09" の形)
    var weekStart: String
    var label: String?
    var color: String?
    var subtitle: String?
    var events: [String]
    var buffer: String?

    var id: String { weekStart }

    enum CodingKeys: String, CodingKey {
        case label, color, subtitle, events, buffer
        case weekStart = "week_start"
    }
}

/// その週にやること(week_goals テーブルの1行)。例: 数学(B・II) 12問のうち 1・2・5 番ができた
struct WeekGoal: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var weekStart: String
    var groupName: String
    var title: String
    var detail: String?
    var targetCount: Int
    /// できた箱の番号(1から)
    var doneBoxes: [Int]
    var sortOrder: Int

    /// できた数
    var doneCount: Int { doneBoxes.count }

    enum CodingKeys: String, CodingKey {
        case id, title, detail
        case weekStart = "week_start"
        case groupName = "group_name"
        case targetCount = "target_count"
        case doneBoxes = "done_boxes"
        case sortOrder = "sort_order"
    }
}

/// グループ(学校・鑑定士など)ごとのやること
struct GoalGroup: Equatable, Identifiable {
    var name: String
    var goals: [WeekGoal]
    var id: String { name }
}

/// 画面に出す1週間ぶん(週の情報 + やること)
struct WeekSection: Equatable, Identifiable {
    var week: WeekPlan
    /// グループは最初に出てきた順
    var groups: [GoalGroup]

    var id: String { week.weekStart }
    var doneCount: Int { groups.flatMap { $0.goals }.reduce(0) { $0 + $1.doneCount } }
    var totalCount: Int { groups.flatMap { $0.goals }.reduce(0) { $0 + $1.targetCount } }

    /// "11/9(月)〜11/15(日)"
    var title: String {
        "\(DayKey.shortText(week.weekStart))〜\(DayKey.shortText(DayKey.adding(6, to: week.weekStart)))"
    }

    /// 週とやることを組み合わせて、週の早い順にならべる
    static func build(weeks: [WeekPlan], goals: [WeekGoal]) -> [WeekSection] {
        let byWeek = Dictionary(grouping: goals, by: \.weekStart)
        return weeks.sorted { $0.weekStart < $1.weekStart }.map { week in
            let sorted = (byWeek[week.weekStart] ?? []).sorted {
                ($0.sortOrder, $0.title) < ($1.sortOrder, $1.title)
            }
            var names: [String] = []
            for goal in sorted where !names.contains(goal.groupName) { names.append(goal.groupName) }
            let groups = names.map { name in GoalGroup(name: name, goals: sorted.filter { $0.groupName == name }) }
            return WeekSection(week: week, groups: groups)
        }
    }

    /// 箱の k 番目(1から)を押したときの、新しいできた箱。
    /// 押した箱だけが切りかわる(まだ → できた、できた → まだ)。小さい順にならべる
    static func doneBoxes(afterTapping box: Int, current: [Int], target: Int) -> [Int] {
        var set = Set(current.filter { (1...target).contains($0) })
        if set.contains(box) {
            set.remove(box)
        } else if (1...target).contains(box) {
            set.insert(box)
        }
        return set.sorted()
    }
}
