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
            // ホーム画面の全サイズで、上に色つきの帯(アイコン・MyStudy・名前・完了の数)を出す
            WidgetFrame(title: "今日の予定", systemImage: "checklist", tint: .blue,
                        trailing: entry.hasData ? "\(entry.doneCount)/\(entry.items.count)" : nil) {
                TodayWidgetView(entry: entry)
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
        // 帯を端までぬるため、OS の余白を切る(中身の余白は WidgetFrame が、ほかの大きさも今までどおりに付け直す)
        .contentMarginsDisabled()
        .configurationDisplayName("今日の予定")
        .description("「今 → 次」と進み具合を表示します。大きいサイズでは、その場でチェックできます。")
        .supportedFamilies(Self.families)
    }

    /// 対応する大きさの一覧(iPhone の特大〔たて長〕は WidgetFamily.withExtraLargePortrait で足す)
    private static var families: [WidgetFamily] {
        WidgetFamily.withExtraLargePortrait([
            .systemSmall, .systemMedium, .systemLarge,                         // ホーム画面
            .systemExtraLarge,                                                 // iPad のホーム画面(特大・横長)
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
        } else if family.isExtraLargePortrait {
            ExtraLargePortraitView(entry: entry)
        } else {
            switch family {
            case .systemSmall: SmallView(entry: entry)
            case .systemMedium: MediumView(entry: entry)
            case .systemLarge: LargeView(entry: entry)
            case .systemExtraLarge: ExtraLargeView(entry: entry)
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
    /// 日付と数の行を出すか(上に帯があるときは、帯と見出しに出ているので出さない)
    var showsHeader = true
    /// 今の予定の題名を何行まで出すか(小・中は帯があってせまいので1行)
    var titleLines = 2

    var body: some View {
        let state = entry.nowNext
        VStack(alignment: .leading, spacing: 4) {
            if showsHeader {
                HStack {
                    Text(DayKey.displayText(entry.dayKey))
                    Spacer(minLength: 4)
                    Text("\(entry.doneCount)/\(entry.items.count)")
                        .monospacedDigit()
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Text("今")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            if let current = state.current {
                Text(current.title)
                    .font(.headline)
                    .lineLimit(titleLines)
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
struct WidgetItemRow: View {
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Text(item.title)
                    .font(.subheadline)
                    .strikethrough(item.done)
                    .foregroundStyle(item.done ? Color.secondary : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - サイズごとの表示

/// 小: 今 → 次
private struct SmallView: View {
    let entry: TodayEntry
    var body: some View { NowNextBlock(entry: entry, showsHeader: false, titleLines: 1) }
}

/// 中: 左に今 → 次、右にまだ終わっていない予定(チェックできる)
private struct MediumView: View {
    let entry: TodayEntry

    var body: some View {
        let remaining = entry.items.filter { !$0.done }
        HStack(alignment: .top, spacing: 12) {
            NowNextBlock(entry: entry, showsHeader: false, titleLines: 1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if remaining.isEmpty {
                Label("全部おわり!", systemImage: "party.popper")
                    .font(.subheadline)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                RowCapacityList(items: remaining, row: { shown, index in WidgetItemRow(item: shown[index]) })
            }
        }
    }
}

/// 日付と進み具合(大・特大たて長の上に出す)
private struct DayHeader: View {
    let entry: TodayEntry
    var large = false

    var body: some View {
        // 完了の数は上の帯に出すので、ここは日付だけ
        Text(DayKey.displayText(entry.dayKey))
            .font(large ? .title3.bold() : .headline)
        ProgressView(value: Double(entry.doneCount), total: Double(max(entry.items.count, 1)))
            .tint(.green)
        if let goal = entry.goal, !goal.isEmpty {
            Label(goal, systemImage: "flag")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

/// 予定の一覧(入るだけ並べる)。予定が無い日は、そう書く
private struct ItemList: View {
    let entry: TodayEntry
    /// 今の予定に色をつけるか(特大たて長)
    var highlightsCurrent = false

    var body: some View {
        if entry.items.isEmpty {
            Text("今日の予定はありません")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            let currentId = highlightsCurrent ? entry.nowNext.current?.id : nil
            RowCapacityList(items: entry.items, pick: TodayEntry.rows, row: { shown, index in
                WidgetItemRow(item: shown[index])
                    .padding(.horizontal, highlightsCurrent ? 6 : 0)
                    .frame(maxHeight: .infinity)
                    .background(
                        shown[index].id == currentId ? Color.accentColor.opacity(0.15) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
            })
        }
    }
}

/// 大: 目標・進み具合・予定の一覧(チェックできる)
private struct LargeView: View {
    let entry: TodayEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DayHeader(entry: entry)
            ItemList(entry: entry)
        }
    }
}

/// 特大(iPad だけ): 左に「今 → 次」、右に予定の一覧(その場でチェックできる)
private struct ExtraLargeView: View {
    let entry: TodayEntry

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text(DayKey.displayText(entry.dayKey))
                    .font(.headline)
                NowNextBlock(entry: entry, showsHeader: false)
                    .fixedSize(horizontal: false, vertical: true)
                if let goal = entry.goal, !goal.isEmpty {
                    Text(goal)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                ProgressView(value: Double(entry.doneCount), total: Double(max(entry.items.count, 1)))
                    .tint(.green)
            }
            .frame(maxWidth: 260, maxHeight: .infinity, alignment: .topLeading)

            ItemList(entry: entry)
        }
    }
}

/// 特大(たて長・iPhone の iOS 27 から): 1日の全体
/// 上から「日付と進み具合・目標」→「今 → 次」→ 1日の予定の一覧(今の予定は色つき、その場でチェックできる)
private struct ExtraLargePortraitView: View {
    let entry: TodayEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DayHeader(entry: entry, large: true)
            // 今 → 次
            // fixedSize: 中身の高さぴったりにする(余った高さでカードが縦にのびて、予定の行が入らなくなるのを防ぐ)
            NowNextBlock(entry: entry, showsHeader: false)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            ItemList(entry: entry, highlightsCurrent: true)
        }
    }
}

extension TodayEntry {
    /// n 行しか入らないときに出す予定。終わった予定から省いて、今とこれからの予定を残す(並びは時刻順のまま)
    static func rows(_ items: [PlanItem], _ n: Int) -> [PlanItem] {
        guard items.count > n else { return items }
        var list = items
        while list.count > n, let index = list.firstIndex(where: \.done) {
            list.remove(at: index)
        }
        return Array(list.prefix(n))
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
