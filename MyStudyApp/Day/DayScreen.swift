import SwiftUI
import UIKit

// メインの画面: 「今→次」・目標・進み具合・予定・やること・ふりかえり を表示します。
struct DayScreen: View {
    let auth: AuthStore
    @State private var store: DayStore
    @State private var showsSignOutConfirm = false
    /// ふりかえりの入力欄にカーソルがあるか(キーボードを閉じるのに使う)
    @FocusState private var isReflectionFocused: Bool
    /// 電波がつながっているかの見張り
    @State private var network = NetworkMonitor()
    /// アプリが前面にあるか・裏に回ったか
    @Environment(\.scenePhase) private var scenePhase

    init(auth: AuthStore, userId: UUID, local: LocalStore) {
        self.auth = auth
        // @State の最初の値を、引数を使って作る書き方
        _store = State(initialValue: DayStore(userId: userId, local: local))
    }

    var body: some View {
        NavigationStack {
            List {
                syncStatusSection

                // 「今 → 次」は、今日を表示しているときだけ出す
                if store.isToday && !store.blocks.isEmpty {
                    Section {
                        NowNextCard(items: store.items)
                    }
                    .listRowBackground(Color.accentColor.opacity(0.12))
                }

                goalSection
                progressSection
                itemSections
                reflectionSection
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .confirmationDialog("ログアウトしますか?", isPresented: $showsSignOutConfirm, titleVisibility: .visible) {
                Button("ログアウト", role: .destructive) {
                    Task { await auth.signOut() }
                }
            } message: {
                if store.pendingCount > 0 {
                    Text("まだサーバーに送れていない変更が \(store.pendingCount) 件あります。ログアウトすると、その変更は消えます。")
                }
            }
            // スクロールするとキーボードが閉じる
            .scrollDismissesKeyboard(.interactively)
            // 下に引っぱって更新(プル・トゥ・リフレッシュ)
            .refreshable { await store.sync() }
            // 左右スワイプで前日・翌日へ
            .simultaneousGesture(daySwipeGesture)
            // 画面が出たときに同期する(Claude が書きこんだ新しい予定がすぐ出るように)
            .task {
                network.start()
                store.setOnline(network.isOnline)
                store.requestSync()
            }
            // 夜の 0:00 をまたいだら、「今日」を新しい日付に進める
            // (id: に今日の日付を渡しているので、日付が変わるたびに次の 0:00 を待ち直す)
            .task(id: store.today) {
                let seconds = DayKey.secondsUntilNextDay()
                try? await Task.sleep(for: .seconds(seconds + 1))
                if !Task.isCancelled {
                    store.refreshToday()
                }
            }
            // アプリが前面に戻った/裏に回ったとき
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    // 開き直したら、日付の変化を確認して同期する
                    store.refreshToday()
                    store.requestSync()
                case .inactive, .background:
                    // 閉じる前に、書きかけのふりかえりを保存する
                    store.saveReflectionIfNeeded()
                @unknown default:
                    break
                }
            }
            // 電波がつながった/切れたとき(つながった瞬間に、たまっていた変更を送る)
            .onChange(of: network.isOnline) { _, online in
                store.setOnline(online)
            }
        }
        // この画面が閉じられたら(ログアウト)、同期を止める
        .onAppear { store.setActive(true) }
        .onDisappear { store.setActive(false) }
    }

    // MARK: - 上のバー(日付の切り替えとメニュー)

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                store.goToPreviousDay()
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("前の日")
        }

        // まん中: 日付。タップすると今日に戻る
        ToolbarItem(placement: .principal) {
            Button {
                store.goToToday()
            } label: {
                VStack(spacing: 0) {
                    Text(DayKey.displayText(store.selectedDate))
                        .font(.headline)
                    if let label = DayKey.relativeLabel(store.selectedDate, today: store.today) {
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("タップすると今日に戻ります")
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                store.goToNextDay()
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("次の日")

            Menu {
                if !store.isToday {
                    Button("今日に戻る", systemImage: "calendar") {
                        store.goToToday()
                    }
                }
                Button("ログアウト", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    showsSignOutConfirm = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("メニュー")
        }

        // キーボードの上に「完了」ボタンを出す
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("完了") { isReflectionFocused = false }
        }
    }

    /// 左右スワイプの判定。横に大きく、たてにはあまり動いていないときだけ日付を変える
    private var daySwipeGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > 80, abs(dx) > abs(dy) * 2 else { return }
                if dx < 0 {
                    store.goToNextDay()      // 左へスワイプ → 翌日
                } else {
                    store.goToPreviousDay()  // 右へスワイプ → 前日
                }
            }
    }

    // MARK: - 同期の状態(オフラインやエラーのお知らせ)

    @ViewBuilder
    private var syncStatusSection: some View {
        switch store.syncProblem {
        case .offline:
            Section {
                Label {
                    Text(store.pendingCount > 0
                         ? "オフラインです。\(store.pendingCount) 件の変更は端末に保存してあり、つながったら自動で送ります。"
                         : "オフラインです。端末に保存してある予定を表示しています。")
                } icon: {
                    Image(systemName: "wifi.slash")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        case .failed(let message):
            Section {
                Label("同期できませんでした。変更は端末に保存してあります。\n\(message)", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        case nil:
            EmptyView()
        }
    }

    // MARK: - 1日の目標

    @ViewBuilder
    private var goalSection: some View {
        if let goal = store.day?.goal, !goal.isEmpty {
            Section("目標") {
                Text(goal)
                    .font(.headline)
            }
        }
    }

    // MARK: - 進み具合(例: 4/9 完了)

    @ViewBuilder
    private var progressSection: some View {
        if store.totalCount > 0 {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(store.doneCount)/\(store.totalCount) 完了")
                            .font(.headline.monospacedDigit())
                        Spacer()
                        if store.doneCount == store.totalCount {
                            Label("全部おわり!", systemImage: "party.popper")
                                .font(.subheadline)
                                .foregroundStyle(.green)
                        }
                    }
                    ProgressView(value: Double(store.doneCount), total: Double(store.totalCount))
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - 予定とやること

    @ViewBuilder
    private var itemSections: some View {
        if store.isWaitingForFirstLoad {
            Section {
                HStack {
                    Spacer()
                    ProgressView("読み込み中…")
                    Spacer()
                }
            }
        } else if store.items.isEmpty && !store.hasPulledSelectedDate {
            // 端末にデータが無く、サーバーからも読めていない(オフラインなど)
            Section {
                ContentUnavailableView(
                    "まだ読みこめていません",
                    systemImage: "icloud.slash",
                    description: Text("電波がつながると、この日の予定を読みこみます。")
                )
            }
        } else if store.items.isEmpty {
            Section {
                ContentUnavailableView(
                    "予定がありません",
                    systemImage: "calendar.badge.plus",
                    description: Text("Claude に予定を作ってもらうと、ここに表示されます。")
                )
            }
        } else {
            if !store.blocks.isEmpty {
                Section("予定") {
                    ForEach(store.blocks) { item in
                        ItemRow(item: item) { toggle(item) }
                    }
                }
            }
            if !store.tasks.isEmpty {
                Section("やること") {
                    ForEach(store.tasks) { item in
                        ItemRow(item: item) { toggle(item) }
                    }
                }
            }
        }
    }

    private func toggle(_ item: PlanItem) {
        // タップしたときに「コツッ」と軽く振動させる
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        store.toggle(item)
    }

    // MARK: - ふりかえり

    @ViewBuilder
    private var reflectionSection: some View {
        Section("ふりかえり") {
            // axis: .vertical で、文字が増えると下に伸びる入力欄になる
            TextField("今日はどうだった?", text: $store.reflectionDraft, axis: .vertical)
                .lineLimit(3...12)
                .focused($isReflectionFocused)

            if store.isReflectionDirty {
                Button("保存") {
                    isReflectionFocused = false
                    store.saveReflection()
                }
            } else if !store.savedReflection.isEmpty {
                Label("保存済み", systemImage: "checkmark")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
