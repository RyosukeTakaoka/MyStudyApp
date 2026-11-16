import SwiftUI
import WidgetKit

// 「今週の計画」ウィジェット: 週・月タブの今週のやることと、箱(例 数学 1〜12)の進み具合。

struct WeekEntry: TimelineEntry {
    let date: Date
    let week: WeekWidgetSnapshot.Week?
    let hasData: Bool

    static func sample(date: Date) -> WeekEntry {
        let monday = DayKey.mondayOfWeek(DayKey.today(now: date))
        let week = WeekWidgetSnapshot.Week(
            weekStart: monday, label: "答練週", subtitle: nil, events: ["土 答練"],
            goals: [
                .init(group: "鑑定理論", title: "基準 総論 1周", target: 6, doneBoxes: [1, 2, 3]),
                .init(group: "民法", title: "過去問", target: 12, doneBoxes: [1, 2, 3, 4, 5]),
                .init(group: "経済", title: "ミクロ 演習", target: 8, doneBoxes: [1]),
            ]
        )
        return WeekEntry(date: date, week: week, hasData: true)
    }
}

struct WeekProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeekEntry { .sample(date: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (WeekEntry) -> Void) {
        let entry = makeEntry(at: Date())
        completion(context.isPreview && entry.week == nil ? .sample(date: Date()) : entry)
    }

    /// 今の表示と、次の月曜 0:00(週が切りかわる)の表示を用意する
    func getTimeline(in context: Context, completion: @escaping (Timeline<WeekEntry>) -> Void) {
        let now = Date()
        let nextMonday = DayKey.adding(7, to: DayKey.mondayOfWeek(DayKey.today(now: now)))
        var entries = [makeEntry(at: now)]
        if let date = DayKey.date(dayKey: nextMonday, minutes: 0), date > now {
            entries.append(makeEntry(at: date))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func makeEntry(at date: Date) -> WeekEntry {
        let snapshot = WeekWidgetStore.read()
        return WeekEntry(date: date, week: snapshot.week(containing: DayKey.today(now: date)),
                         hasData: !snapshot.weeks.isEmpty)
    }
}

struct WeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WeekWidgetStore.kind, provider: WeekProvider()) { entry in
            WeekWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("今週の計画")
        .description("週・月タブの今週のやることと、箱の進み具合を表示します。")
        .supportedFamilies(WidgetFamily.withExtraLargePortrait([
            .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge, .accessoryRectangular,
        ]))
    }
}

struct WeekWidgetView: View {
    let entry: WeekEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let week = entry.week {
            if family.isExtraLargePortrait {
                WeekListView(week: week, maxGoals: 16, showsEvents: true)
            } else {
                switch family {
                case .systemSmall: WeekSmallView(week: week)
                case .systemMedium: WeekListView(week: week, maxGoals: 3, showsEvents: false)
                case .systemLarge: WeekListView(week: week, maxGoals: 8, showsEvents: true)
                case .systemExtraLarge: WeekWideView(week: week)
                case .accessoryRectangular: WeekLockView(week: week)
                default: WeekSmallView(week: week)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Label("今週の計画", systemImage: "rectangle.stack")
                    .font(.caption.bold())
                Text(entry.hasData ? "今週の計画はまだありません" : "アプリを開くと表示されます")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 部品

/// 週の見出し(日付・ラベル・全体の進み具合)
private struct WeekHeader: View {
    let week: WeekWidgetSnapshot.Week

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(week.rangeText)
                    .font(.headline)
                if let label = week.label, !label.isEmpty {
                    Text(label)
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.18), in: Capsule())
                }
                Spacer(minLength: 0)
                Text("\(week.done)/\(week.total)")
                    .font(.subheadline.monospacedDigit().bold())
                    .foregroundStyle(week.total > 0 && week.done >= week.total ? Color.green : Color.primary)
            }
            ProgressView(value: Double(week.done), total: Double(max(week.total, 1)))
                .tint(.green)
        }
    }
}

/// やること1つ: 題名・数・箱の列(緑 = 済み)
private struct WidgetGoalRow: View {
    let goal: WeekWidgetSnapshot.Goal

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(goal.title)
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(goal.done)/\(goal.target)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(goal.target > 0 && goal.done >= goal.target ? Color.green : Color.secondary)
            }
            BoxStrip(goal: goal)
        }
    }
}

/// 箱の列。箱が多すぎる(30より多い)ときは、ふつうの進み具合のバーにする
private struct BoxStrip: View {
    let goal: WeekWidgetSnapshot.Goal

    var body: some View {
        if goal.target > 0 && goal.target <= 30 {
            let done = Set(goal.doneBoxes)
            HStack(spacing: 2) {
                ForEach(1...goal.target, id: \.self) { box in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(done.contains(box) ? Color.green : Color.secondary.opacity(0.25))
                        .frame(height: 7)
                }
            }
        } else {
            ProgressView(value: Double(goal.done), total: Double(max(goal.target, 1)))
                .tint(.green)
        }
    }
}

/// 小: 今週の進み具合(大きな数字)
private struct WeekSmallView: View {
    let week: WeekWidgetSnapshot.Week

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("今週", systemImage: "rectangle.stack")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            if let label = week.label, !label.isEmpty {
                Text(label)
                    .font(.caption.bold())
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text("\(week.done)/\(week.total)")
                .font(.title.monospacedDigit().bold())
            ProgressView(value: Double(week.done), total: Double(max(week.total, 1)))
                .tint(.green)
            Text("\(week.goals.filter { $0.target > 0 && $0.done >= $0.target }.count)/\(week.goals.count) 項目 完了")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 中・大・特大(たて長): 見出し + やることの一覧
private struct WeekListView: View {
    let week: WeekWidgetSnapshot.Week
    let maxGoals: Int
    let showsEvents: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WeekHeader(week: week)
            if showsEvents && !week.events.isEmpty {
                Label(week.events.joined(separator: " ・ "), systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            GoalGroupList(goals: Array(week.goals.prefix(maxGoals)), showsGroups: maxGoals > 3)
            if week.goals.count > maxGoals {
                Text("ほか \(week.goals.count - maxGoals) 件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

/// 特大(iPad・横長): 左に見出しと行事、右にやること
private struct WeekWideView: View {
    let week: WeekWidgetSnapshot.Week

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                WeekHeader(week: week)
                if let subtitle = week.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                ForEach(week.events, id: \.self) { event in
                    Label(event, systemImage: "calendar")
                        .font(.caption)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: 260, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                GoalGroupList(goals: Array(week.goals.prefix(8)), showsGroups: true)
                if week.goals.count > 8 {
                    Text("ほか \(week.goals.count - 8) 件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// やることを、グループ(科目など)の見出しつきで並べる
private struct GoalGroupList: View {
    let goals: [WeekWidgetSnapshot.Goal]
    let showsGroups: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(goals.enumerated()), id: \.offset) { index, goal in
                if showsGroups, !goal.group.isEmpty, index == 0 || goals[index - 1].group != goal.group {
                    Text(goal.group)
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .padding(.top, index == 0 ? 0 : 2)
                }
                WidgetGoalRow(goal: goal)
            }
        }
    }
}

/// ロック画面: 今週の進み具合
private struct WeekLockView: View {
    let week: WeekWidgetSnapshot.Week

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(week.label.map { "今週 \($0)" } ?? "今週の計画")
                .font(.caption.bold())
                .lineLimit(1)
            Text("\(week.done)/\(week.total)")
                .font(.headline.monospacedDigit())
            ProgressView(value: Double(week.done), total: Double(max(week.total, 1)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
