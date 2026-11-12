import FamilyControls
import SwiftUI

// 集中モード(スクリーンタイム)の設定画面。
struct FocusSettingsView: View {
    @Bindable var screenTime: ScreenTimeController
    @AppStorage(AppSettings.focusDuringTimerKey) private var duringTimer = true
    @AppStorage(AppSettings.focusAutoBlocksKey) private var autoBlocks = false
    @State private var showsPicker = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("勉強中は、選んだアプリ(Anki など)以外を開けないようにします。時間になると自動で解除されます。")
                        .font(.subheadline)
                }

                Section("1. スクリーンタイムの許可") {
                    if screenTime.isAuthorized {
                        Label("許可されています", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("スクリーンタイムの使用を許可する") {
                            Task { await screenTime.requestAuthorization() }
                        }
                    }
                }

                Section {
                    Button("使ってよいアプリを選ぶ") { showsPicker = true }
                        .disabled(!screenTime.isAuthorized)
                    LabeledContent("選んだアプリ", value: "\(screenTime.allowedAppCount) 個")
                } header: {
                    Text("2. 使ってよいアプリ")
                } footer: {
                    Text("必ず「Anki」と、この「MyStudy」アプリを選んでください。MyStudy を選ばないと、集中モード中にこのアプリも開けなくなります。「教育」などのカテゴリごとの選択は反映されないので、アプリを1つずつ選んでください。")
                }

                Section {
                    Toggle("タイマー中", isOn: $duringTimer)
                    Toggle("予定ブロックの時間(自動)", isOn: $autoBlocks)
                } header: {
                    Text("3. いつ集中モードにするか")
                } footer: {
                    Text("「予定ブロックの時間」をオンにすると、アプリを閉じていても予定の開始時刻に始まり、終了時刻に解除されます。チェックを付けると、その予定の集中モードは終わります。15分未満の予定は対象外です。")
                }

                Section("今すぐ集中モード") {
                    if let until = screenTime.activeUntil {
                        Label("集中モード中(\(until.formatted(date: .omitted, time: .shortened)) まで)", systemImage: "lock.fill")
                        Button("今すぐ終える", role: .destructive) { screenTime.endNow() }
                    } else {
                        ForEach([25, 50, 90], id: \.self) { minutes in
                            Button("\(minutes)分 集中する") { screenTime.startManual(minutes: minutes) }
                                .disabled(!screenTime.isReady)
                        }
                    }
                }

                if let message = screenTime.errorMessage {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            // Apple が用意しているアプリ選択画面(このアプリには、選んだアプリの名前は見えない仕組み)
            .familyActivityPicker(isPresented: $showsPicker, selection: $screenTime.selection)
            .navigationTitle("集中モード")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .onAppear { screenTime.refresh() }
        }
    }
}
