import ActivityKit
import SwiftUI
import WidgetKit

// ライブアクティビティ: タイマー中の予定を、ロック画面とダイナミックアイランドに表示します。
// 経過時間と進み具合のバーは、表示側が自動で進めるので、アプリが閉じていても動きます。
struct StudyLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StudyActivityAttributes.self) { context in
            // ロック画面・通知センターに出る表示
            LiveActivityLockView(state: context.state)
                .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                // 長押しで広げたときの表示
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.subject, systemImage: "book.fill")
                        .font(.caption)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.startedAt, style: .timer)
                        .font(.title3.bold().monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 90)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.title)
                            .font(.headline)
                            .lineLimit(1)
                        PlannedProgress(state: context.state)
                        NextLine(state: context.state)
                    }
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundStyle(.green)
            } compactTrailing: {
                Text(context.state.startedAt, style: .timer)
                    .monospacedDigit()
                    .frame(maxWidth: 56)
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(.green)
            }
        }
    }
}

private struct LiveActivityLockView: View {
    let state: StudyActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("勉強中", systemImage: "timer")
                    .font(.caption.bold())
                Spacer()
                Text(state.subject)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(state.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(state.startedAt, style: .timer)
                    .font(.title2.bold().monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 110)
            }
            PlannedProgress(state: state)
            NextLine(state: state)
        }
    }
}

/// 予定の終了時刻までの進み具合のバー
private struct PlannedProgress: View {
    let state: StudyActivityAttributes.ContentState

    var body: some View {
        if let end = state.plannedEnd, end > state.startedAt {
            ProgressView(timerInterval: state.startedAt...end, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(.green)
        }
    }
}

/// 「次 17:30 経済 ミクロ 演習」
private struct NextLine: View {
    let state: StudyActivityAttributes.ContentState

    var body: some View {
        if let title = state.nextTitle, let start = state.nextStart {
            Text("次 \(TimeOfDay.text(DayKey.minutesOfDay(start))) \(title)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
