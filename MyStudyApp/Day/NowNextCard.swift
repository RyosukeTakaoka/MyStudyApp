import SwiftUI

// 画面のいちばん上に出す「今 → 次」のカード。
struct NowNextCard: View {
    let items: [PlanItem]
    /// タイマーが動いている予定(その予定には開始ボタンを出さない)
    var runningItemIds: Set<UUID> = []
    /// 「タイマー開始」が押されたとき
    var onStartTimer: ((PlanItem) -> Void)? = nil

    var body: some View {
        // TimelineView は、決まったタイミングで中身を描き直してくれる部品。
        // .everyMinute で、毎分0秒に「今の時刻」が新しくなる
        TimelineView(.everyMinute) { context in
            let state = NowNext.compute(
                items: items,
                nowMinutes: DayKey.minutesOfDay(context.date)
            )

            VStack(alignment: .leading, spacing: 14) {
                // --- 今 ---
                VStack(alignment: .leading, spacing: 4) {
                    Text("今")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    if let current = state.current {
                        HStack(alignment: .firstTextBaseline) {
                            Text(current.title)
                                .font(.title2.bold())
                            if current.done {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        Text(detail(for: current, prefix: "あと", minutes: state.minutesLeft))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if !runningItemIds.contains(current.id), !current.done, let onStartTimer {
                            Button {
                                onStartTimer(current)
                            } label: {
                                Label("タイマー開始", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .padding(.top, 4)
                        }
                    } else {
                        Text("予定なし")
                            .font(.title2.bold())
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // --- 次 ---
                VStack(alignment: .leading, spacing: 4) {
                    Label("次", systemImage: "arrow.right")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    if let next = state.next {
                        Text(next.title)
                            .font(.headline)
                        Text(detail(for: next, prefix: "開始まで", minutes: state.minutesUntilNext))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else {
                        Text("このあとの予定はありません")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
    }

    /// 「16:30〜17:30 ・ あと25分」のような文字を作る
    private func detail(for item: PlanItem, prefix: String, minutes: Int?) -> String {
        var parts: [String] = []
        if let time = item.timeRangeText { parts.append(time) }
        if let minutes, minutes > 0 { parts.append("\(prefix)\(NowNext.durationText(minutes))") }
        return parts.joined(separator: " ・ ")
    }
}
