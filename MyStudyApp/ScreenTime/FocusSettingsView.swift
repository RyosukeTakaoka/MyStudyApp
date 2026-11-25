import FamilyControls
import SwiftUI

// 集中モード(スクリーンタイム)の設定画面。
struct FocusSettingsView: View {
    @Bindable var screenTime: ScreenTimeController
    @AppStorage(AppSettings.focusDuringTimerKey) private var duringTimer = true
    @AppStorage(AppSettings.focusAutoBlocksKey) private var autoBlocks = true
    @State private var showsPicker = false
    /// 常時ブロックのアプリを選ぶ画面
    @State private var showsPermanentPicker = false
    @State private var permanentSelection = PermanentBlockStore.apps()
    @State private var showsNiconicoPicker = false
    @State private var niconicoSelection = PermanentBlockStore.niconicoApps()
    /// 自分で足すサイトの入力欄
    @State private var newDomain = ""
    @State private var domainMessage: String?
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

                // 登録してある自動の時間帯(予定の時間になると、自動で集中モードになる)
                Section {
                    if screenTime.registeredBlocks.isEmpty {
                        Text(autoBlocks ? "登録してある時間帯はありません(今日・明日の勉強の予定が無いか、まだ同期していません)" : "自動はオフです")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(screenTime.registeredBlocks, id: \.name) { window in
                            Text("\(window.start.formatted(.dateTime.month().day().hour().minute()))〜\(window.end.formatted(date: .omitted, time: .shortened))")
                                .font(.subheadline.monospacedDigit())
                        }
                    }
                    if let problem = screenTime.registrationProblem {
                        Text(problem)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("自動で集中モードになる時間帯")
                } footer: {
                    Text("時間になると、アプリを閉じていても集中モードになります。もしならなかったときも、アプリを開けばすぐにかかります。")
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

                permanentSection

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

    // MARK: - 常時ブロック(365日24時間)

    private var permanentSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label("いつでも止めているもの", systemImage: "nosign")
                    .font(.subheadline.bold())
                Text("サイト: YouTube(www・m・youtu.be もふくむ)・X(twitter.com もふくむ)・Instagram・TikTok・Invidious(公開ホストの一覧を自動で更新)")
                    .font(.caption)
                Text("2027年1月1日から: ニコニコ動画(nicovideo.jp・nico.ms)も止める")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let updated = PermanentBlockStore.invidiousUpdatedAt {
                    Text("Invidious の一覧: \(PermanentBlockStore.invidiousHosts.count) 件(\(updated.formatted(date: .abbreviated, time: .omitted)) に更新)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            // まだ見られるサイトを見つけたら、ここで足す(足すだけで、外せない)
            HStack {
                TextField("止めるサイトを足す(例: yewtu.be)", text: $newDomain)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button("足す") {
                    if screenTime.addPermanentDomain(newDomain) {
                        domainMessage = "「\(PermanentBlockList.normalize(newDomain))」を止めました。"
                        newDomain = ""
                    } else {
                        domainMessage = "サイトの名前(例: yewtu.be)を入れてください。"
                    }
                }
                .disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty || !screenTime.isAuthorized)
            }
            if let domainMessage {
                Text(domainMessage).font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup("止めているサイト(\(screenTime.permanentDomains.count) 件)") {
                Text(screenTime.permanentDomains.joined(separator: "\n"))
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
            Button("止めるアプリを足す(YouTube・X・Instagram・TikTok)") { showsPermanentPicker = true }
                .disabled(!screenTime.isAuthorized)
                .familyActivityPicker(isPresented: $showsPermanentPicker, selection: $permanentSelection)
            LabeledContent("止めているアプリ", value: "\(screenTime.permanentAppCount) 個")
            Button("1月1日から止めるアプリを足す(ニコニコ動画)") { showsNiconicoPicker = true }
                .disabled(!screenTime.isAuthorized)
                .familyActivityPicker(isPresented: $showsNiconicoPicker, selection: $niconicoSelection)
            LabeledContent("1月1日から止めるアプリ", value: "\(screenTime.niconicoAppCount) 個")
        } header: {
            Text("常時ブロック(365日24時間)")
        } footer: {
            Text("集中モードとは別に、いつでも止めます。このアプリの中には外すボタンがありません(アプリは足すことだけできます。選ぶ画面で外しても、外れません)。サイトは Safari などのブラウザで開けなくなります。アプリは Apple の画面で1つずつ選んでください(このアプリには、アプリの名前は見えない仕組みです)。")
        }
        .onChange(of: permanentSelection) { _, selection in
            screenTime.addPermanentApps(selection)
            permanentSelection = PermanentBlockStore.apps()
        }
        .onChange(of: niconicoSelection) { _, selection in
            screenTime.addNiconicoApps(selection)
            niconicoSelection = PermanentBlockStore.niconicoApps()
        }
    }
}
