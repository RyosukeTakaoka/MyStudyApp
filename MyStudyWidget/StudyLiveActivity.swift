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
                    ElapsedText(state: context.state)
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
                Image(systemName: context.state.pausedElapsed == nil ? "timer" : "pause.fill")
                    .foregroundStyle(context.state.pausedElapsed == nil ? Color.green : Color.orange)
            } compactTrailing: {
                ElapsedText(state: context.state)
                    .monospacedDigit()
                    .frame(maxWidth: 56)
            } minimal: {
                Image(systemName: context.state.pausedElapsed == nil ? "timer" : "pause.fill")
                    .foregroundStyle(context.state.pausedElapsed == nil ? Color.green : Color.orange)
            }
        }
    }
}

private struct LiveActivityLockView: View {
    let state: StudyActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(state.pausedElapsed == nil ? "勉強中" : "一時停止中",
                      systemImage: state.pausedElapsed == nil ? "timer" : "pause.fill")
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
                ElapsedText(state: state)
                    .font(.title2.bold().monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 110)
            }
            PlannedProgress(state: state)
            NextLine(state: state)
        }
    }
}

/// 経過時間。動いているときは自動で数え、一時停止中は止まった時間を出す
private struct ElapsedText: View {
    let state: StudyActivityAttributes.ContentState

    var body: some View {
        if let paused = state.pausedElapsed {
            Text(NowNext.clockText(paused))
        } else {
            Text(state.startedAt, style: .timer)
        }
    }
}

/// 予定の終了時刻までの進み具合のバー(一時停止中は出さない)
private struct PlannedProgress: View {
    let state: StudyActivityAttributes.ContentState

    var body: some View {
        if state.pausedElapsed == nil, let end = state.plannedEnd, end > state.startedAt {
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
