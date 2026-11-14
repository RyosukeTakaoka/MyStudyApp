import SwiftUI

// 予定を足す・直す画面。
struct ItemEditorSheet: View {
    /// 直すときは元の予定、足すときは nil
    let original: PlanItem?
    /// 足すときの日付
    let date: String
    /// 保存ボタンが押されたとき(できあがった内容を渡す)
    let onSave: (ItemDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: ItemDraft
    @State private var errorMessage: String?

    init(original: PlanItem?, date: String, onSave: @escaping (ItemDraft) -> Void) {
        self.original = original
        self.date = date
        self.onSave = onSave
        _draft = State(initialValue: original.map(ItemDraft.init(item:)) ?? ItemDraft(date: date))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("種類", selection: $draft.isBlock) {
                        Text("時間つきの予定").tag(true)
                        Text("やること").tag(false)
                    }
                    .pickerStyle(.segmented)
                }

                Section("内容") {
                    TextField("題名(例: 民法 物権 過去問)", text: $draft.title)
                    Picker("科目", selection: $draft.subject) {
                        ForEach(ItemDraft.subjects(including: draft.subject), id: \.self) { subject in
                            Text(subject).tag(subject)
                        }
                    }
                    TextField("メモ(任意)", text: $draft.note, axis: .vertical)
                        .lineLimit(1...4)
                }

                if draft.isBlock {
                    Section("時間") {
                        DatePicker("開始", selection: $draft.start, displayedComponents: .hourAndMinute)
                        Toggle("終わりの時刻を決める", isOn: $draft.hasEnd)
                        if draft.hasEnd {
                            DatePicker("終了", selection: $draft.end, displayedComponents: .hourAndMinute)
                        }
                    }
                }

                if let original, original.source == "claude" {
                    Section {
                        Text("Claude が入れた予定を直すと「自分で入れた予定」になり、Claude が予定を入れ直しても消えなくなります。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(original == nil ? "予定を足す" : "予定を直す")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if let problem = draft.problem {
                            errorMessage = problem
                        } else {
                            onSave(draft)
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}
