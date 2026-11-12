import SwiftUI

// 予定・タスクの1行。行のどこをタップしてもチェックが切りかわります。
struct ItemRow: View {
    let item: PlanItem
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
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
                }

                Spacer(minLength: 8)
                SubjectTag(subject: item.subject)
            }
            // 文字のない余白の部分もタップできるようにする
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // VoiceOver(読み上げ)用の説明
        .accessibilityLabel("\(item.timeRangeText ?? "") \(item.title) \(item.subject)")
        .accessibilityValue(item.done ? "完了" : "未完了")
    }
}
