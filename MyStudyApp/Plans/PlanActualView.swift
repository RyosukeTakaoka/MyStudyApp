import SwiftUI

// 「予定と実績」の画面(週の表)。週カードの「予定と実績」から開く。
// 日ごと・科目ごとに「予定○分 / 実績○分」と、1日の目標時間に対して何%かを出す。
struct PlanActualView: View {
    let weekStart: String
    @Environment(\.dismiss) private var dismiss
    @State private var week: PlanActualWeek?
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            List {
                if let problem {
                    Section {
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if let week {
                    Section {
                        HStack {
                            total("予定", week.plannedMinutes)
                            total("実績", week.actualMinutes)
                            total("目標", week.targetMinutes)
                            VStack(spacing: 2) {
                                Text("達成").font(.caption).foregroundStyle(.secondary)
                                Text("\(week.percentOfTarget)%").font(.headline.monospacedDigit())
                                    .foregroundStyle(color(week.percentOfTarget))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }

                    Section {
                        ForEach(week.days) { day in
                            DayRow(day: day)
                        }
                    } header: {
                        Text("日ごと")
                    } footer: {
                        Text("目標は Claude が決めた1日の勉強時間(決めていない日は 平日4時間・土日8時間)。生活の予定は入れていません。")
                    }

                    if !week.subjects.isEmpty {
                        Section("科目ごと") {
                            ForEach(week.subjects) { row in
                                HStack {
                                    SubjectTag(subject: row.subject)
                                    Spacer()
                                    Text("予定 \(NowNext.durationText(row.plannedMinutes))")
                                        .foregroundStyle(.secondary)
                                    Text("実績 \(NowNext.durationText(row.actualMinutes))")
                                        .bold()
                                }
                                .font(.subheadline.monospacedDigit())
                            }
                        }
                    }
                } else if problem == nil {
                    HStack {
                        Spacer()
                        ProgressView("読み込み中…")
                        Spacer()
                    }
                }
            }
            .navigationTitle("予定と実績 \(DayKey.shortText(weekStart))〜")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func total(_ title: String, _ minutes: Int) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(NowNext.durationText(minutes)).font(.subheadline.bold().monospacedDigit())
        }
        .frame(maxWidth: .infinity)
    }

    private func load() async {
        let end = DayKey.adding(6, to: weekStart)
        do {
            async let items = RemoteAPI().fetchItems(from: weekStart, to: end)
            async let days = RemoteAPI().fetchDays(from: weekStart, to: end)
            week = PlanActualWeek.build(items: try await items, days: try await days, weekStart: weekStart)
            problem = nil
        } catch {
            problem = "読みこめませんでした。電波を確かめて、下に引っぱって読み直してください。"
        }
    }
}

/// 1日の行: 曜日・予定・実績・目標に対する%(バーつき)
private struct DayRow: View {
    let day: PlanActualDay

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(DayKey.shortText(day.dayKey))
                    .font(.subheadline.bold())
                Spacer()
                Text("予定 \(NowNext.durationText(day.plannedMinutes))")
                    .foregroundStyle(.secondary)
                Text("実績 \(NowNext.durationText(day.actualMinutes))")
                    .bold()
            }
            .font(.subheadline.monospacedDigit())
            HStack(spacing: 8) {
                ProgressView(value: Double(min(day.actualMinutes, day.targetMinutes)), total: Double(max(day.targetMinutes, 1)))
                    .tint(color(day.percentOfTarget))
                Text("目標 \(NowNext.durationText(day.targetMinutes)) の \(day.percentOfTarget)%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(color(day.percentOfTarget))
                    .fixedSize()
            }
        }
        .padding(.vertical, 2)
    }
}

/// 達成の割合の色(80%以上 緑、50%以上 オレンジ、それ未満 赤)
private func color(_ percent: Int) -> Color {
    percent >= 80 ? .green : percent >= 50 ? .orange : .red
}
