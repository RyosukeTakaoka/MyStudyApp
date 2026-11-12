import SwiftUI

// 月のカレンダー。日ごとの達成率を色の濃さで表し、タップするとその日に移動します。
// 下には、その月の勉強時間(科目別)を表示します。
struct CalendarScreen: View {
    let today: String
    let selectedDate: String
    /// 期間を指定して予定を読む関数(DayStore.items(from:to:))
    let loadItems: (String, String) async -> [PlanItem]
    /// 日付がタップされたとき
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var monthStart: String
    @State private var items: [PlanItem] = []
    @State private var isLoading = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdays = ["日", "月", "火", "水", "木", "金", "土"]

    init(today: String, selectedDate: String,
         loadItems: @escaping (String, String) async -> [PlanItem],
         onSelect: @escaping (String) -> Void) {
        self.today = today
        self.selectedDate = selectedDate
        self.loadItems = loadItems
        self.onSelect = onSelect
        _monthStart = State(initialValue: CalendarMath.monthStart(of: selectedDate))
    }

    var body: some View {
        let stats = CalendarMath.stats(items)
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    monthHeader
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(weekdays, id: \.self) { day in
                            Text(day)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Array(CalendarMath.grid(monthStart: monthStart).enumerated()), id: \.offset) { _, key in
                            if let key {
                                dayCell(key, stat: stats[key])
                            } else {
                                Color.clear.frame(height: 44)
                            }
                        }
                    }
                    summary(stats: stats)
                }
                .padding()
            }
            .navigationTitle("カレンダー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            // 月が変わるたびに読みこむ
            .task(id: monthStart) {
                isLoading = true
                items = await loadItems(monthStart, CalendarMath.monthEnd(monthStart))
                isLoading = false
            }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                monthStart = CalendarMath.addingMonths(-1, to: monthStart)
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("前の月")
            Spacer()
            Text(CalendarMath.monthTitle(monthStart))
                .font(.title3.bold())
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
            Spacer()
            Button {
                monthStart = CalendarMath.addingMonths(1, to: monthStart)
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("次の月")
        }
    }

    /// 1日ぶんのマス。予定があれば達成率に応じて緑が濃くなる
    private func dayCell(_ key: String, stat: DayStat?) -> some View {
        let dayNumber = Int(key.suffix(2)) ?? 0
        let isToday = key == today
        let isSelected = key == selectedDate
        let fill: Color = {
            guard let stat, stat.total > 0 else { return Color.clear }
            return Color.green.opacity(0.15 + 0.6 * stat.ratio)
        }()

        return Button {
            onSelect(key)
            dismiss()
        } label: {
            VStack(spacing: 2) {
                Text("\(dayNumber)")
                    .font(.subheadline.weight(isToday ? .bold : .regular))
                if let stat, stat.total > 0 {
                    Text("\(stat.done)/\(stat.total)")
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text(" ")
                        .font(.system(size: 9))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(fill, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : (isToday ? Color.secondary : Color.clear), lineWidth: 1.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(DayKey.displayText(key))
    }

    /// その月の集計
    private func summary(stats: [String: DayStat]) -> some View {
        let total = stats.values.reduce(DayStat()) { sum, s in
            DayStat(total: sum.total + s.total, done: sum.done + s.done, minutes: sum.minutes + s.minutes)
        }
        let bySubject = CalendarMath.minutesBySubject(items)

        return VStack(alignment: .leading, spacing: 10) {
            Text("この月のまとめ")
                .font(.headline)
            HStack {
                Label("\(total.done)/\(total.total) 完了", systemImage: "checkmark.circle")
                Spacer()
                Label(NowNext.durationText(total.minutes), systemImage: "timer")
            }
            .font(.subheadline.monospacedDigit())

            if bySubject.isEmpty {
                Text("タイマーで勉強時間を記録すると、科目ごとの時間がここに出ます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(bySubject) { row in
                    HStack {
                        SubjectTag(subject: row.subject)
                        Spacer()
                        Text(NowNext.durationText(row.minutes))
                            .font(.subheadline.monospacedDigit())
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}
