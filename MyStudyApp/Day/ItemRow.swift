import SwiftUI

// 予定・タスクの1行。
//   ・タップ  → チェックが切りかわる
//   ・長押し  → すぐにタイマーが始まる(メニューは出さない)
struct ItemRow: View {
    let item: PlanItem
    let onToggle: () -> Void
    /// 長押しされたとき(タイマー開始)
    var onLongPress: (() -> Void)? = nil
    /// この予定のタイマーが動いているか(行に印を出す)
    var isTimerRunning = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // チェックの丸
            Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(item.done ? Color.green : Color.secondary)

            VStack(alignment: .leading, spacing: 3) {
                if let time = item.timeRangeText {
                    Text(time)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(item.title)
                    .strikethrough(item.done)
                    .foregroundStyle(item.done ? Color.secondary : Color.primary)
                if let note = item.note, !note.isEmpty {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let minutes = item.actualMinutes, minutes > 0 {
                    Label("実績 \(NowNext.durationText(minutes))", systemImage: "timer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)
            if isTimerRunning {
                Image(systemName: "timer")
                    .foregroundStyle(.green)
                    .accessibilityLabel("タイマー中")
            }
            SubjectTag(subject: item.subject)
        }
        // 文字のない余白の部分も押せるようにする
        .contentShape(Rectangle())
        // 短く押したらチェック、0.4秒以上押したらタイマー開始
        .onTapGesture(perform: onToggle)
        .onLongPressGesture(minimumDuration: 0.4) {
            onLongPress?()
        }
        // VoiceOver(読み上げ)用の説明と操作
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.timeRangeText ?? "") \(item.title) \(item.subject)")
        .accessibilityValue(item.done ? "完了" : "未完了")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onToggle() }
        .accessibilityAction(named: "タイマーを開始") { onLongPress?() }
    }
}
