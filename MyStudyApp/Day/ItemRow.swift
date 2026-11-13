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
    /// 「手順と注意」を開いているか
    @State private var showsGuide = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            mainRow
            if item.hasGuide {
                guideToggle
                if showsGuide {
                    GuideBox(steps: item.steps, cautions: item.cautions)
                }
            }
        }
    }

    /// 「▶ 手順と注意」のボタン(押すと開く・閉じる。チェックは切りかわらない)
    private var guideToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { showsGuide.toggle() }
        } label: {
            Label("手順と注意", systemImage: showsGuide ? "chevron.down" : "chevron.right")
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .padding(.leading, 40)   // チェックの丸の分だけ右にずらして、題名とそろえる
        .accessibilityLabel(showsGuide ? "手順と注意を閉じる" : "手順と注意を開く")
    }

    /// 1行目: チェック・時刻・題名・科目
    private var mainRow: some View {
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

/// 手順(番号つき)と注意(箇条書き)を表示する箱
struct GuideBox: View {
    let steps: [String]
    let cautions: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !steps.isEmpty {
                Text("手順")
                    .font(.subheadline.bold())
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(index + 1).")
                                .monospacedDigit()
                            Text(step)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if !cautions.isEmpty {
                Text("注意")
                    .font(.subheadline.bold())
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(cautions.enumerated()), id: \.offset) { _, caution in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("・")
                            Text(caution)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .font(.subheadline)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .padding(.leading, 40)
    }
}
