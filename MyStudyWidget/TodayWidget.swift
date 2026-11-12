import AppIntents
import SwiftUI
import WidgetKit

// MARK: - データ

/// ウィジェットが表示する1コマぶんのデータ
struct TodayEntry: TimelineEntry {
    let date: Date
    let dayKey: String
    let goal: String?
    let items: [PlanItem]
    /// アプリから一度でもデータを受け取ったか(未ログインなどで空なら false)
    let hasData: Bool

    var doneCount: Int { items.filter(\.done).count }
    var nowNext: NowNext { NowNext.compute(items: items, nowMinutes: DayKey.minutesOfDay(date)) }

    func date(ofMinutes minutes: Int?) -> Date? {
        minutes.flatMap { DayKey.date(dayKey: dayKey, minutes: $0) }
    }

    /// ウィジェットを選ぶ画面に出す見本
    static func sample(date: Date) -> TodayEntry {
        let key = DayKey.today(now: date)
        let now = DayKey.minutesOfDay(date)
        func block(_ start: Int, _ end: Int, _ title: String, _ subject: String, done: Bool = false) -> PlanItem {
            PlanItem(id: UUID(), date: key, kind: "block",
                     startTime: TimeOfDay.text(max(0, min(start, 1439))), endTime: TimeOfDay.text(max(0, min(end, 1439))),
                     title: title, subject: subject, sortOrder: 0, source: "claude",
                     done: done, doneAt: nil, actualMinutes: nil, note: nil)
        }
        let items = [
            block(now - 60, now - 20, "Anki 鑑定評価基準", "鑑定理論", done: true),
            block(now - 10, now + 30, "民法 物権 過去問", "民法"),
            block(now + 40, now + 100, "経済 ミクロ 演習", "経済"),
        ]
        return TodayEntry(date: date, dayKey: key, goal: "鑑定評価基準 総論を1周", items: items, hasData: true)
    }
}

/// いつ・どんな表示にするかを WidgetKit に教える係
struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        .sample(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        let entry = makeEntry(at: Date(), snapshot: SharedStore.readSnapshot())
        completion(context.isPreview && !entry.hasData ? .sample(date: Date()) : entry)
    }

    /// 予定の開始・終了の時刻ごとに表示を用意しておく(アプリを開かなくても「今 → 次」が進む)
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let snapshot = SharedStore.readSnapshot()
        let now = Date()
        let todayKey = DayKey.today(now: now)
        let dates = [now] + WidgetTimeline.refreshDates(items: snapshot.day(todayKey).items, dayKey: todayKey, now: now)
        let entries = dates.map { makeEntry(at: $0, snapshot: snapshot) }
        // .atEnd = 最後の表示(夜0時)になったら、新しい予定表を作り直してもらう
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func makeEntry(at date: Date, snapshot: WidgetSnapshot) -> TodayEntry {
        let key = DayKey.today(now: date)
        let day = snapshot.day(key)
        return TodayEntry(date: date, dayKey: key, goal: day.goal, items: day.items, hasData: !snapshot.days.isEmpty)
    }
}

// MARK: - ウィジェット本体

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidget", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("今日の予定")
        .description("「今 → 次」と進み具合を表示します。大きいサイズでは、その場でチェックできます。")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,                         // ホーム画面
            .accessoryCircular, .accessoryRectangular, .accessoryInline,       // ロック画面
        ])
    }
}

/// 大きさ(family)ごとに表示を切りかえる
struct TodayWidgetView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if !entry.hasData {
            Text("アプリを開いてログインしてください")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            switch family {
            case .systemSmall: SmallView(entry: entry)
            case .systemMedium: MediumView(entry: entry)
            case .systemLarge: LargeView(entry: entry)
            case .accessoryCircular: CircularView(entry: entry)
            case .accessoryRectangular: RectangularView(entry: entry)
            case .accessoryInline: InlineView(entry: entry)
            default: SmallView(entry: entry)
            }
        }
    }
}

// MARK: - 部品

/// 「今」と「次」(小・中サイズの左側で使う)
private struct NowNextBlock: View {
    let entry: TodayEntry

    var body: some View {
        let state = entry.nowNext
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(DayKey.displayText(entry.dayKey))
                Spacer(minLength: 4)
                Text("\(entry.doneCount)/\(entry.items.count)")
                    .monospacedDigit()
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Text("今")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            if let current = state.current {
                Text(current.title)
                    .font(.headline)
                    .lineLimit(2)
                    .strikethrough(current.done)
                if let end = entry.date(ofMinutes: current.endMinutes) {
                    // style: .timer で、終了までの残り時間が自動で減っていく
                    (Text("あと ") + Text(end, style: .timer))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("予定なし")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if let next = state.next, let start = next.startMinutes {
                Text("次 \(TimeOfDay.text(start)) \(next.title)")
                    .font(.caption)
                    .lineLimit(1)
            }
        }
    }
}

/// チェックボタンつきの1行(押すとアプリを開かずにチェックできる)
private struct WidgetItemRow: View {
    let item: PlanItem

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: ToggleItemIntent(itemId: item.id)) {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.done ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 0) {
                if let time = item.timeRangeText {
                    Text(time)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(item.title)
                    .font(.subheadline)
                    .strikethrough(item.done)
                    .foregroundStyle(item.done ? Color.secondary : Color.primary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - サイズごとの表示

/// 小: 今 → 次
private struct SmallView: View {
    let entry: TodayEntry
    var body: some View { NowNextBlock(entry: entry) }
}

/// 中: 左に今 → 次、右にまだ終わっていない予定(チェックできる)
private struct MediumView: View {
    let entry: TodayEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            NowNextBlock(entry: entry)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                let remaining = entry.items.filter { !$0.done }
                if remaining.isEmpty {
                    Label("全部おわり!", systemImage: "party.popper")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                } else {
                    ForEach(remaining.prefix(3)) { item in
                        WidgetItemRow(item: item)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 大: 目標・進み具合・予定の一覧(チェックできる)
private struct LargeView: View {
    let entry: TodayEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(DayKey.displayText(entry.dayKey))
                    .font(.headline)
                Spacer()
                Text("\(entry.doneCount)/\(entry.items.count) 完了")
                    .font(.subheadline.monospacedDigit())
            }
            if let goal = entry.goal, !goal.isEmpty {
                Text(goal)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            ProgressView(value: Double(entry.doneCount), total: Double(max(entry.items.count, 1)))

            if entry.items.isEmpty {
                Text("今日の予定はありません")
                    .foregroundStyle(.secondary)
            }
            ForEach(entry.items.prefix(7)) { item in
                WidgetItemRow(item: item)
            }
            if entry.items.count > 7 {
                Text("ほか \(entry.items.count - 7) 件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

/// ロック画面(丸): 進み具合のメーター
private struct CircularView: View {
    let entry: TodayEntry

    var body: some View {
        Gauge(value: Double(entry.doneCount), in: 0...Double(max(entry.items.count, 1))) {
            Image(systemName: "checklist")
        } currentValueLabel: {
            Text("\(entry.doneCount)/\(entry.items.count)")
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }
}

/// ロック画面(長方形): 今の予定と残り時間、次の予定
private struct RectangularView: View {
    let entry: TodayEntry

    var body: some View {
        let state = entry.nowNext
        VStack(alignment: .leading, spacing: 1) {
            if let current = state.current {
                Text(current.title)
                    .font(.headline)
                    .lineLimit(1)
                    .widgetAccentable()
                if let end = entry.date(ofMinutes: current.endMinutes) {
                    (Text("あと ") + Text(end, style: .timer))
                        .font(.caption.monospacedDigit())
                }
            } else {
                Text("今は予定なし")
                    .font(.headline)
            }
            if let next = state.next, let start = next.startMinutes {
                Text("次 \(TimeOfDay.text(start)) \(next.title)")
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// ロック画面(時計の上の1行)
private struct InlineView: View {
    let entry: TodayEntry

    var body: some View {
        let state = entry.nowNext
        if let current = state.current {
            Text("今: \(current.title)")
        } else if let next = state.next, let start = next.startMinutes {
            Text("次 \(TimeOfDay.text(start)) \(next.title)")
        } else {
            Text("\(entry.doneCount)/\(entry.items.count) 完了")
        }
    }
}
