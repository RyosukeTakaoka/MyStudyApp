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
    /// 勉強時間のタイマー
    @State private var timer = StudyTimer()
    @State private var showsCalendar = false
    /// タイマーまでスクロールする合図(数字が増えるたびに移動する)
    @State private var scrollToTimerRequest = 0
    /// 集中モード(スクリーンタイム)
    @State private var screenTime = ScreenTimeController()
    @State private var showsFocusSettings = false
    @AppStorage(AppSettings.focusDuringTimerKey) private var focusDuringTimer = true
    @AppStorage(AppSettings.focusAutoBlocksKey) private var focusAutoBlocks = false
    /// iPhone のカレンダー連携
    @AppStorage(AppSettings.calendarSyncKey) private var calendarSyncEnabled = false
    /// 表示中の日の、ほかのカレンダーの予定
    @State private var calendarEvents: [CalendarEventInfo] = []
    /// 設定(端末に保存される)
    @AppStorage(AppSettings.autoTimerKey) private var autoTimerEnabled = true
    @AppStorage(AppSettings.remindersKey) private var remindersEnabled = false
    /// アプリが前面にあるか・裏に回ったか
    @Environment(\.scenePhase) private var scenePhase

    init(auth: AuthStore, userId: UUID, local: LocalStore) {
        self.auth = auth
        // @State の最初の値を、引数を使って作る書き方
        _store = State(initialValue: DayStore(userId: userId, local: local))
    }

    var body: some View {
        NavigationStack {
            // ScrollViewReader: 「この行まで移動して」とスクロールを命令できるようにする入れ物
            ScrollViewReader { proxy in
            List {
                syncStatusSection
                focusSection
                timerSection

                // 「今 → 次」は、今日を表示しているときだけ出す
                if store.isToday && !store.blocks.isEmpty {
                    Section {
                        NowNextCard(
                            items: store.items,
                            isTimerRunning: timer.running != nil,
                            onStartTimer: { startTimer(for: $0, isAuto: false) }
                        )
                    }
                    .listRowBackground(Color.accentColor.opacity(0.12))
                }

                goalSection
                progressSection
                calendarEventsSection
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
                // ウィジェット用のデータが変わったら、共有フォルダに書き出す
                store.onSnapshotChanged = { WidgetBridge.publish($0) }
                store.applyWidgetToggles(SharedStore.takePendingToggles())
                store.setOnline(network.isOnline)
                store.requestSync()
                restoreLiveActivity()
                screenTime.refresh()
                checkAutoTimer()
            }
            // 画面が出ているあいだ、30秒ごとに自動タイマーの開始・終了を確かめる
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    checkAutoTimer()
                    screenTime.refresh()
                }
            }
            // 同期が終わるたびに、通知を予約しなおす(Claude が予定を変えても通知が合うように)
            .task(id: store.lastSyncSucceededAt) {
                await rescheduleReminders()
                rescheduleFocus()
                exportToCalendar()
                checkAutoTimer()
            }
            // 表示する日が変わったら、その日のカレンダーの予定を読む
            .task(id: "\(store.selectedDate)|\(calendarSyncEnabled)") {
                loadCalendarEvents()
            }
            .onChange(of: calendarSyncEnabled) { _, enabled in
                Task {
                    if enabled, !(await CalendarSync.requestAccess()) {
                        calendarSyncEnabled = false   // 許可されなかったらオフに戻す
                        return
                    }
                    exportToCalendar()
                    loadCalendarEvents()
                }
            }
            .onChange(of: focusAutoBlocks) { _, _ in
                rescheduleFocus()
            }
            // 予定をチェックしたら、その予定の自動の集中モードを外す
            .onChange(of: store.doneCount) { _, _ in
                rescheduleFocus()
                exportToCalendar()   // チェックを付けたら、カレンダーの題名にも ✓ を付ける
            }
            .sheet(isPresented: $showsFocusSettings, onDismiss: rescheduleFocus) {
                FocusSettingsView(screenTime: screenTime)
            }
            .onChange(of: remindersEnabled) { _, enabled in
                Task {
                    if enabled, !(await NotificationScheduler.requestPermission()) {
                        remindersEnabled = false   // 許可されなかったらオフに戻す
                    }
                    await rescheduleReminders()
                }
            }
            .onChange(of: autoTimerEnabled) { _, _ in
                checkAutoTimer()
            }
            .sheet(isPresented: $showsCalendar) {
                CalendarScreen(
                    today: store.today,
                    selectedDate: store.selectedDate,
                    loadItems: { from, to in await store.items(from: from, to: to) },
                    onSelect: { store.select($0) }
                )
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
                    // 開き直したら、ウィジェットでのチェックを取りこみ、日付の変化を確認して同期する
                    store.applyWidgetToggles(SharedStore.takePendingToggles())
                    store.refreshToday()
                    store.requestSync()
                    screenTime.refresh()
                    loadCalendarEvents()
                    checkAutoTimer()
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
            // 長押しでタイマーを始めたら、いちばん上のタイマーまで移動する
            .onChange(of: scrollToTimerRequest) { _, _ in
                Task { @MainActor in
                    // タイマーの欄が画面に作られるのを少し待ってから移動する
                    try? await Task.sleep(for: .milliseconds(80))
                    withAnimation(.easeInOut) {
                        proxy.scrollTo(Self.timerRowID, anchor: .top)
                    }
                }
            }
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

            Button {
                showsCalendar = true
            } label: {
                Image(systemName: "calendar")
            }
            .accessibilityLabel("カレンダー")

            Menu {
                Toggle(isOn: $autoTimerEnabled) {
                    Label("自動タイマー", systemImage: "timer")
                }
                Toggle(isOn: $remindersEnabled) {
                    Label("開始時刻に通知", systemImage: "bell")
                }
                Toggle(isOn: $calendarSyncEnabled) {
                    Label("カレンダーと連携", systemImage: "calendar.badge.clock")
                }
                Button("集中モード(スクリーンタイム)…", systemImage: "lock.shield") {
                    showsFocusSettings = true
                }
                Divider()
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

    // MARK: - タイマー

    /// タイマーの欄の目印(スクロールで移動するときに使う)
    private static let timerRowID = "timer-row"

    @ViewBuilder
    private var timerSection: some View {
        if let running = timer.running {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        if running.isPaused {
                            Label("一時停止中", systemImage: "pause.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.orange)
                        } else {
                            Label(running.isAuto ? "勉強中(自動)" : "勉強中", systemImage: "timer")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        SubjectTag(subject: running.subject)
                    }
                    Text(running.title)
                        .font(.title3.bold())
                    Group {
                        if running.isPaused {
                            // 一時停止中は、止めたときの時間をそのまま出す
                            Text(NowNext.clockText(running.priorSeconds + running.accumulatedSeconds))
                                .foregroundStyle(.secondary)
                        } else {
                            // style: .timer は、その時刻からの経過時間を自動で数えて表示する。
                            // 「これまでの記録」と「一時停止」の分だけずらした時刻を渡すので、続きから数える
                            Text(running.displayStart, style: .timer)
                        }
                    }
                    .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                    if running.priorSeconds > 0 {
                        Text("前回までの記録 \(NowNext.durationText(Int(running.priorSeconds / 60))) をふくむ")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // 1段目: 一時停止 / 再開(いちばん押しやすい大きなボタン)
                    Button {
                        togglePause()
                    } label: {
                        Label(running.isPaused ? "再開" : "一時停止",
                              systemImage: running.isPaused ? "play.fill" : "pause.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(running.isPaused ? .green : .orange)

                    // 2段目: 終わらせるボタン(どちらも、それまでの時間を記録する)
                    HStack(spacing: 12) {
                        Button {
                            stopTimer(markDone: true)
                        } label: {
                            Label("完了", systemImage: "checkmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            stopTimer(markDone: false)
                        } label: {
                            Label("記録して終了", systemImage: "stop.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 4)
                .id(Self.timerRowID)
            }
        }
    }

    /// タイマーを始める(ライブアクティビティも出す)
    private func startTimer(for item: PlanItem, isAuto: Bool) {
        let plannedEnd = item.endMinutes.flatMap { DayKey.date(dayKey: item.date, minutes: $0) }
        let running = RunningTimer(
            itemId: item.id,
            title: item.title,
            subject: item.subject,
            startedAt: Date(),
            plannedEnd: plannedEnd,
            isAuto: isAuto,
            // この予定ですでに記録してある時間(「記録して終了」したあとにまた始めたとき、続きから表示する)
            priorSeconds: TimeInterval(currentActualMinutes(of: item) * 60),
            itemDate: item.date
        )
        timer.start(running)
        showLiveActivity(for: running)
        if focusDuringTimer && screenTime.isReady {
            screenTime.startForTimer(plannedEnd: plannedEnd)
        }
    }

    /// その予定の、いちばん新しい記録(分)。画面のリストを優先し、無ければ渡された値を使う
    private func currentActualMinutes(of item: PlanItem) -> Int {
        let latest = store.items.first { $0.id == item.id }
            ?? store.upcomingItems(days: 0).first { $0.id == item.id }
            ?? item
        return latest.actualMinutes ?? 0
    }

    /// 一時停止 ⇄ 再開。一時停止中は、タイマーでかけた集中モードも外す
    private func togglePause() {
        guard let running = timer.running else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if running.isPaused {
            timer.resume(now: Date())
            if focusDuringTimer && screenTime.isReady {
                screenTime.startForTimer(plannedEnd: running.plannedEnd)
            }
        } else {
            // 一時停止までの区間を記録に残す
            store.recordSession(timer.pause(now: Date()))
            screenTime.endForTimer()
        }
        // ライブアクティビティも、止まった時間/続きの時間に出し直す
        if let updated = timer.running {
            showLiveActivity(for: updated)
        }
    }

    /// タイマーを止めて、勉強時間を記録する。
    /// reason: 記録に残す止めた理由(省略すると、完了なら done、そうでなければ stop)
    private func stopTimer(markDone: Bool, reason: String? = nil) {
        guard let result = timer.stop(now: Date(), reason: reason ?? (markDone ? "done" : "stop")) else { return }
        store.recordSession(result.session)
        LiveActivityController.endAll()
        screenTime.endForTimer()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        store.recordStudy(itemId: result.itemId, minutes: result.minutes, markDone: markDone)
    }

    /// 自動タイマー: 予定の時間になったら始め、終了時刻を過ぎたら止める
    private func checkAutoTimer() {
        // 自動で始めたタイマーは、設定に関係なく終了時刻で止める
        if timer.shouldAutoStop(now: Date()) {
            stopTimer(markDone: false, reason: "auto")
        }
        guard autoTimerEnabled, scenePhase == .active else { return }
        let todayItems = store.upcomingItems(days: 0)
        if let item = timer.autoStartCandidate(
            items: todayItems,
            dayKey: store.today,
            nowMinutes: DayKey.minutesOfDay(Date())
        ) {
            timer.markAutoStarted(item, dayKey: store.today)
            startTimer(for: item, isAuto: true)
        }
    }

    /// ライブアクティビティを出す(次の予定も一緒に表示する)
    private func showLiveActivity(for running: RunningTimer) {
        let todayItems = store.upcomingItems(days: 0)
        let startedMinutes = DayKey.minutesOfDay(running.startedAt)
        let next = NowNext.compute(items: todayItems, nowMinutes: startedMinutes).next
        let nextStart = next.flatMap { item in
            item.startMinutes.flatMap { DayKey.date(dayKey: item.date, minutes: $0) }
        }
        LiveActivityController.start(running, nextTitle: next?.title, nextStart: nextStart)
    }

    /// アプリを開き直したとき、タイマーが動いているのにライブアクティビティが消えていたら出し直す
    private func restoreLiveActivity() {
        if let running = timer.running, !LiveActivityController.isShowing {
            showLiveActivity(for: running)
        }
    }

    // MARK: - カレンダー連携

    /// 今日から7日分の予定ブロックを「MyStudy」カレンダーに書き出す
    private func exportToCalendar() {
        guard calendarSyncEnabled else { return }
        CalendarSync.export(
            items: store.upcomingItems(days: 7),
            from: store.today,
            to: DayKey.adding(7, to: store.today)
        )
    }

    private func loadCalendarEvents() {
        calendarEvents = calendarSyncEnabled ? CalendarSync.events(on: store.selectedDate) : []
    }

    /// ほかのカレンダー(学校・Google など)の予定
    @ViewBuilder
    private var calendarEventsSection: some View {
        if !calendarEvents.isEmpty {
            Section("カレンダーの予定") {
                ForEach(calendarEvents) { event in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(event.isAllDay
                             ? "終日"
                             : "\(TimeOfDay.text(DayKey.minutesOfDay(event.start)))〜\(TimeOfDay.text(DayKey.minutesOfDay(event.end)))")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                            Text(event.calendarTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    /// 予定ブロックの自動の集中モードを登録しなおす
    private func rescheduleFocus() {
        screenTime.rescheduleBlocks(items: store.upcomingItems(days: 1), enabled: focusAutoBlocks)
    }

    /// 集中モード中のお知らせ
    @ViewBuilder
    private var focusSection: some View {
        if let until = screenTime.activeUntil {
            Section {
                HStack {
                    Label("集中モード中(\(until.formatted(date: .omitted, time: .shortened)) まで)", systemImage: "lock.fill")
                        .font(.subheadline)
                    Spacer()
                    Button("終える") { screenTime.endNow() }
                        .buttonStyle(.borderless)
                        .font(.subheadline)
                }
            }
        }
    }

    /// 通知を予約しなおす(オフなら全部消す)
    private func rescheduleReminders() async {
        if remindersEnabled {
            await NotificationScheduler.reschedule(
                ReminderPlan.make(items: store.upcomingItems(days: 7), now: Date())
            )
        } else {
            await NotificationScheduler.removeAll()
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
                        itemRow(item)
                    }
                }
            }
            if !store.tasks.isEmpty {
                Section("やること") {
                    ForEach(store.tasks) { item in
                        itemRow(item)
                    }
                }
            }
        }
    }

    private func itemRow(_ item: PlanItem) -> some View {
        ItemRow(
            item: item,
            onToggle: { toggle(item) },
            onLongPress: { startTimerByLongPress(item) },
            isTimerRunning: timer.running?.itemId == item.id
        )
    }

    /// 長押しでタイマー開始。ほかの予定のタイマーが動いていたら、それを記録して止めてから始める
    private func startTimerByLongPress(_ item: PlanItem) {
        if let running = timer.running {
            if running.itemId == item.id { return }   // 同じ予定なら何もしない
            stopTimer(markDone: false, reason: "switch")
        }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        startTimer(for: item, isAuto: false)
        scrollToTimerRequest += 1   // 数字が変わると、上の onChange が動いてタイマーまで移動する
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
