import AppIntents
import SwiftUI
import WidgetKit

// 「タイマー」ウィジェット: 動いているタイマーの経過時間と、一時停止・完了・終了のボタン。
// ボタンを押すと、アプリを開かずにタイマーを操作できます(記録はアプリが取りこんでサーバーへ送る)。

struct TimerEntry: TimelineEntry {
    let date: Date
    /// 動いている(一時停止中もふくむ)タイマー
    let timers: [RunningTimer]
    /// タイマーが無いときに出す「今の予定」
    let currentTitle: String?
    let hasData: Bool

    static func sample(date: Date) -> TimerEntry {
        let timer = RunningTimer(itemId: UUID(), title: "民法 物権 過去問", subject: "民法",
                                 startedAt: date.addingTimeInterval(-25 * 60), plannedEnd: nil, isAuto: false)
        return TimerEntry(date: date, timers: [timer], currentTitle: nil, hasData: true)
    }
}

struct TimerProvider: TimelineProvider {
    func placeholder(in context: Context) -> TimerEntry { .sample(date: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (TimerEntry) -> Void) {
        let entry = makeEntry(at: Date())
        completion(context.isPreview && entry.timers.isEmpty ? .sample(date: Date()) : entry)
    }

    /// 経過時間は表示側が自動で数えるので、「今の予定」が変わる時刻だけ表示を用意する。
    /// タイマーを始める・止めるとアプリが描き直しを頼む
    func getTimeline(in context: Context, completion: @escaping (Timeline<TimerEntry>) -> Void) {
        let now = Date()
        let snapshot = SharedStore.readSnapshot()
        let todayKey = DayKey.today(now: now)
        let dates = [now] + WidgetTimeline.refreshDates(items: snapshot.day(todayKey).items, dayKey: todayKey, now: now)
        completion(Timeline(entries: dates.map { makeEntry(at: $0, snapshot: snapshot) }, policy: .atEnd))
    }

    private func makeEntry(at date: Date, snapshot: WidgetSnapshot = SharedStore.readSnapshot()) -> TimerEntry {
        let items = snapshot.day(DayKey.today(now: date)).items
        let current = NowNext.compute(items: items, nowMinutes: DayKey.minutesOfDay(date)).current
        return TimerEntry(date: date, timers: TimerWidgetKind.savedTimers(), currentTitle: current?.title,
                          hasData: !snapshot.days.isEmpty)
    }
}

struct TimerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TimerWidgetKind.kind, provider: TimerProvider()) { entry in
            WidgetFrame(title: "タイマー", systemImage: "timer", tint: .orange,
                        trailing: entry.timers.isEmpty ? "停止中" : "\(entry.timers.count) 個") {
                TimerWidgetView(entry: entry)
            }
                .containerBackground(.fill.tertiary, for: .widget)
        }
        // 帯を端までぬるため、OS の余白を切る(中身の余白は WidgetFrame が付け直す)
        .contentMarginsDisabled()
        .configurationDisplayName("勉強タイマー")
        .description("動いているタイマーの経過時間を表示し、一時停止・完了・終了をその場で押せます。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct TimerWidgetView: View {
    let entry: TimerEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if !entry.hasData && entry.timers.isEmpty {
            Text("アプリを開いてログインしてください")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if entry.timers.isEmpty {
            NoTimerView(entry: entry, compact: family == .systemSmall || family == .accessoryRectangular)
        } else {
            switch family {
            case .accessoryRectangular:
                LockTimerView(timer: entry.timers[0], now: entry.date, more: entry.timers.count - 1)
            case .systemSmall:
                SmallTimerView(timer: entry.timers[0], now: entry.date, more: entry.timers.count - 1)
            case .systemMedium:
                TimerList(entry: entry, maxRows: 2)
            default:
                TimerList(entry: entry, maxRows: 6)
            }
        }
    }
}

// MARK: - 部品

/// 経過時間(動いていれば自動で数える。一時停止中は止まった時間)
private struct ElapsedView: View {
    let timer: RunningTimer
    let now: Date

    var body: some View {
        if timer.isPaused {
            Text(ElapsedFormat.text(timer.displaySeconds(now: now)))
                .foregroundStyle(.orange)
        } else {
            // style: .timer = その時刻からの経過時間を、表示側が1秒ごとに数える
            Text(timer.displayStart, style: .timer)
        }
    }
}

/// 一時停止・再開/完了/終了のボタン
private struct TimerButtons: View {
    let timer: RunningTimer
    var size: CGFloat = 36

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: ToggleTimerPauseIntent(itemId: timer.itemId)) {
                circle(timer.isPaused ? "play.fill" : "pause.fill", color: timer.isPaused ? .green : .orange)
            }
            .accessibilityLabel(timer.isPaused ? "再開" : "一時停止")
            Button(intent: StopTimerIntent(itemId: timer.itemId, markDone: true)) {
                circle("checkmark", color: .green)
            }
            .accessibilityLabel("完了")
            Button(intent: StopTimerIntent(itemId: timer.itemId, markDone: false)) {
                circle("stop.fill", color: .secondary)
            }
            .accessibilityLabel("記録して終了")
        }
        .buttonStyle(.plain)
    }

    private func circle(_ name: String, color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: size * 0.4, weight: .bold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.18), in: Circle())
    }
}

/// 小: タイマー1つ
private struct SmallTimerView: View {
    let timer: RunningTimer
    let now: Date
    let more: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(timer.isPaused ? "一時停止中" : "勉強中", systemImage: "timer")
                    .font(.caption2.bold())
                    .foregroundStyle(timer.isPaused ? Color.orange : Color.accentColor)
                Spacer(minLength: 0)
                if more > 0 {
                    Text("+\(more)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(timer.title)
                .font(.subheadline.bold())
                .lineLimit(1)
            ElapsedView(timer: timer, now: now)
                .font(.title2.monospacedDigit().bold())
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            TimerButtons(timer: timer, size: 32)
        }
    }
}

/// 中・大: タイマーの一覧(枠に入るだけ並べる)
private struct TimerList: View {
    let entry: TimerEntry
    let maxRows: Int

    var body: some View {
        FitRows(
            items: entry.timers,
            maxCount: maxRows,
            spacing: 8,
            dividers: true,
            header: { EmptyView() },
            row: { shown, index in
                let timer = shown[index]
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(timer.title)
                            .font(.subheadline.bold())
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            ElapsedView(timer: timer, now: entry.date)
                                .font(.title3.monospacedDigit().bold())
                            if timer.isPaused {
                                Text("一時停止中")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    TimerButtons(timer: timer)
                }
            }
        )
    }
}

/// ロック画面: タイマー1つ(ボタンなし)
private struct LockTimerView: View {
    let timer: RunningTimer
    let now: Date
    let more: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(more > 0 ? "\(timer.title) ほか\(more)" : timer.title)
                .font(.caption.bold())
                .lineLimit(1)
            ElapsedView(timer: timer, now: now)
                .font(.title3.monospacedDigit().bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// タイマーが無いとき
private struct NoTimerView: View {
    let entry: TimerEntry
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("タイマーは止まっています", systemImage: "timer")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            if let title = entry.currentTitle {
                Text("今: \(title)")
                    .font(.subheadline)
                    .lineLimit(2)
            }
            if !compact {
                Text("アプリで予定を長押しすると始まります")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
