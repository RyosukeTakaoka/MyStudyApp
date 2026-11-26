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
    /// どのタイマーまで移動するか
    @State private var scrollTargetItemId: UUID?
    /// 予定を足す画面を出しているか
    @State private var showsAddItem = false
    /// 直している予定(nil なら画面を出さない)
    @State private var editingItem: PlanItem?
    /// 集中モード(スクリーンタイム)
    @State private var screenTime = ScreenTimeController()
    @State private var showsFocusSettings = false
    @AppStorage(AppSettings.focusDuringTimerKey) private var focusDuringTimer = true
    @AppStorage(AppSettings.focusAutoBlocksKey) private var focusAutoBlocks = true
    /// iPhone のカレンダー連携
    @AppStorage(AppSettings.calendarSyncKey) private var calendarSyncEnabled = false
    /// 表示中の日の、ほかのカレンダーの予定
    @State private var calendarEvents: [CalendarEventInfo] = []
    /// 最後にウィジェットへ渡したデータ(カレンダーの予定を足して渡し直すときに使う)
    @State private var lastWidgetSnapshot: WidgetSnapshot?
    /// 設定(端末に保存される)
    @AppStorage(AppSettings.autoTimerKey) private var autoTimerEnabled = false
    @AppStorage(AppSettings.remindersKey) private var remindersEnabled = false
    /// アプリが前面にあるか・裏に回ったか
    @Environment(\.scenePhase) private var scenePhase
    /// 画面の横幅の種類(iPad の広い画面だと .regular、iPhone の縦向きだと .compact)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// ログインしている人の id(タイマーをサーバーで共有するときに使う)
    private let userId: UUID
    /// 表示している日の夜の睡眠(ほかの予定と同じように一覧に出す)
    @State private var daySleeps: [SleepPlan] = []
    /// 上の帯(試験まで○日・次の答練・累計時間)
    @State private var targetBand = TargetBandStore()
    /// タイマーの共有の通信中か / 通信中にもう一度頼まれたか
    @State private var isSyncingTimers = false
    @State private var timerSyncAgain = false

    init(auth: AuthStore, userId: UUID, local: LocalStore) {
        self.auth = auth
        self.userId = userId
        // @State の最初の値を、引数を使って作る書き方
        _store = State(initialValue: DayStore(userId: userId, local: local))
    }

    var body: some View {
        NavigationStack {
            // ScrollViewReader: 「この行まで移動して」とスクロールを命令できるようにする入れ物
            ScrollViewReader { proxy in
            dayLists
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
            // ※ 画面全体の「左右スワイプで日付を変える」は、予定の行のスワイプ(編集・明日へ・削除)と
            //   ぶつかって勝手に翌日へ進んでしまうのでやめた。日付は上の矢印・日付・📅 で変える
            // 画面が出たときに同期する(Claude が書きこんだ新しい予定がすぐ出るように)
            .task {
                network.start()
                // ウィジェット用のデータが変わったら、共有フォルダに書き出す
                store.onSnapshotChanged = { snapshot in
                    lastWidgetSnapshot = snapshot
                    publishWidget(snapshot)
                }
                applyWidgetToggles()
                applyWidgetTimerEvents()
                store.setOnline(network.isOnline)
                store.requestSync()
                restoreLiveActivity()
                screenTime.refresh()
                checkAutoTimer()
                requestTimerSync()
                // 常時ブロックの Invidious の一覧を新しくする(1週間に1回まで)
                await screenTime.updateInvidiousList()
            }
            // 画面が出ているあいだ、30秒ごとに自動タイマーの開始・終了を確かめる
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    checkAutoTimer()
                    screenTime.refresh()
                    // ほかの端末(iPhone / iPad)で始めた・止めたタイマーを取りこむ
                    requestTimerSync()
                }
            }
            // 同期が終わるたびに、通知を予約しなおす(Claude が予定を変えても通知が合うように)
            .task(id: store.lastSyncSucceededAt) {
                await targetBand.refresh(today: store.today)
                await rescheduleReminders()
                rescheduleFocus()
                exportToCalendar()
                checkAutoTimer()
            }
            // 表示する日が変わったら、その日のカレンダーの予定を読む
            .task(id: "\(store.selectedDate)|\(calendarSyncEnabled)") {
                loadCalendarEvents()
            }
            // 表示する日の睡眠を読む(日が変わったとき・同期が終わったとき)
            .task(id: "\(store.selectedDate)|\(store.lastSyncSucceededAt?.timeIntervalSince1970 ?? 0)") {
                await loadDaySleeps()
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
            .onChange(of: focusAutoBlocks) { _, enabled in
                rescheduleFocus()
                // オンにしたのに、スクリーンタイムの許可や使ってよいアプリの選択がまだなら、設定画面を開く
                if enabled && !screenTime.isReady {
                    showsFocusSettings = true
                }
            }
            // 予定をチェックしたら、その予定の自動の集中モードを外す
            .onChange(of: store.doneCount) { _, _ in
                rescheduleFocus()
                exportToCalendar()   // チェックを付けたら、カレンダーの題名にも ✓ を付ける
            }
            .sheet(isPresented: $showsFocusSettings, onDismiss: rescheduleFocus) {
                FocusSettingsView(screenTime: screenTime)
            }
            // 予定を足す画面
            .sheet(isPresented: $showsAddItem) {
                ItemEditorSheet(original: nil, date: store.selectedDate) { draft in
                    store.addItem(date: draft.date, kind: draft.isBlock ? "block" : "task",
                                  startTime: draft.startTimeText, endTime: draft.endTimeText,
                                  title: draft.trimmedTitle, subject: draft.subject, note: draft.noteOrNil)
                }
            }
            // 予定を直す画面
            .sheet(item: $editingItem) { item in
                ItemEditorSheet(original: item, date: item.date) { draft in
                    // 題名・時刻などが変わったときだけ「直した予定」にする(実績だけ直したときは、そのまま)
                    let edited = draft.applied(to: item)
                    if edited != item {
                        store.updateItem(edited)
                    }
                    if draft.actualOverrideValue != item.actualOverride {
                        store.setActualOverride(itemId: item.id, minutes: draft.actualOverrideValue)
                    }
                }
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
                    applyWidgetToggles()
                    applyWidgetTimerEvents()
                    requestTimerSync()
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
            // ウィジェットのボタンでタイマーが一時停止・終了されたとき
            .onReceive(NotificationCenter.default.publisher(for: .studyTimerChangedFromWidget)) { _ in
                applyWidgetTimerEvents()
            }
            // 電波がつながった/切れたとき(つながった瞬間に、たまっていた変更を送る)
            .onChange(of: network.isOnline) { _, online in
                store.setOnline(online)
                if online { requestTimerSync() }
            }
            // この端末でタイマーを変えたら(始めた・一時停止・再開・終了)、すぐサーバーへ送る
            .onChange(of: timer.timers) { _, _ in
                if !timer.dirtyItemIds.isEmpty { requestTimerSync() }
            }
            // 長押しでタイマーを始めたら、いちばん上のタイマーまで移動する
            .onChange(of: scrollToTimerRequest) { _, _ in
                Task { @MainActor in
                    // タイマーの欄が画面に作られるのを少し待ってから移動する
                    try? await Task.sleep(for: .milliseconds(80))
                    withAnimation(.easeInOut) {
                        if let itemId = scrollTargetItemId {
                            proxy.scrollTo(Self.timerRowID(itemId), anchor: .top)
                        }
                    }
                }
            }
            }
        }
        // この画面が閉じられたら(ログアウト)、同期を止める
        .onAppear { store.setActive(true) }
        .onDisappear { store.setActive(false) }
    }

    // MARK: - 画面の並べ方(iPhone は1列、iPad は2列)

    /// iPhone: 今までどおり1列に全部ならべる。
    /// iPad(横幅が広いとき): 左に「タイマー・今→次・予定」、右に「グラフ・目標・進み具合・カレンダー・ふりかえり」。
    @ViewBuilder
    private var dayLists: some View {
        if horizontalSizeClass == .regular {
            // GeometryReader: 画面の幅を読みとる入れ物(右の列の幅を決めるのに使う)
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    List {
                        targetBandSection
                        syncStatusSection
                        focusSection
                        timerSection
                        nowNextSection
                        itemSections
                    }
                    Divider()
                    List {
                        chartSection
                        goalSection
                        progressSection
                        calendarEventsSection
                        reflectionSection
                    }
                    // 右の列は画面の4割くらい(広すぎず狭すぎず)
                    .frame(width: min(420, max(320, geometry.size.width * 0.4)))
                }
            }
        } else {
            List {
                targetBandSection
                syncStatusSection
                focusSection
                timerSection
                nowNextSection
                chartSection
                goalSection
                progressSection
                calendarEventsSection
                itemSections
                reflectionSection
            }
        }
    }

    /// いちばん上の帯(今日を表示しているときだけ)
    @ViewBuilder
    private var targetBandSection: some View {
        if store.isToday, let data = targetBand.data {
            TargetBandSection(data: data, today: store.today)
        }
    }

    /// 「今 → 次」は、今日を表示しているときだけ出す
    @ViewBuilder
    private var nowNextSection: some View {
        if store.isToday && !store.blocks.isEmpty {
            Section {
                NowNextCard(
                    items: store.items + sleepItems,
                    calendarEvents: store.selectedDate == store.today ? calendarEvents : [],
                    runningItemIds: Set(timer.timers.map(\.itemId)),
                    onStartTimer: { startTimer(for: $0, isAuto: false) }
                )
            }
            .listRowBackground(Color.accentColor.opacity(0.12))
        }
    }

    /// 終わった日(昨日より前)だけ、勉強した時間帯の円グラフを出す(その日が終わるまでは出さない)
    @ViewBuilder
    private var chartSection: some View {
        if store.selectedDate <= store.today {
            // 今日の分は、タイマーを止めて同期するたびに描き直す
            DayChartSection(dayKey: store.selectedDate, refreshKey: store.lastSyncSucceededAt)
        }
    }

    /// 表示している日の夜の睡眠を、予定の1行の形にしたもの
    private var sleepItems: [PlanItem] {
        daySleeps.filter { $0.night == store.selectedDate }.map { $0.asPlanItem() }
    }

    /// 予定(時間つき)に睡眠を混ぜて、時刻順に並べたもの
    private var blocksWithSleep: [PlanItem] {
        (store.blocks + sleepItems).sorted {
            ($0.startMinutes ?? 0, $0.sortOrder) < ($1.startMinutes ?? 0, $1.sortOrder)
        }
    }

    /// 表示している日の睡眠を読む(読めなければ、端末に取っておいた分)
    private func loadDaySleeps() async {
        let night = store.selectedDate
        if let sleeps = await loadSleeps(fromNight: night, toNight: night) {
            daySleeps = sleeps
        }
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

            Button {
                showsAddItem = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("予定を足す")

            Menu {
                // 自動タイマーは使わないので、メニューには「予定の時間に自動で集中モード」を出す
                // (自動タイマーの設定はオフのまま残る)
                Toggle(isOn: $focusAutoBlocks) {
                    Label("予定の時間に自動で集中モード", systemImage: "lock.fill")
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

    // MARK: - タイマー

    /// タイマーのカードの目印(スクロールで移動するときに使う)
    private static func timerRowID(_ itemId: UUID) -> String { "timer-\(itemId.uuidString)" }

    /// 動いているタイマーのカード(いくつでも並ぶ)
    @ViewBuilder
    private var timerSection: some View {
        ForEach(timer.timers, id: \.itemId) { running in
            Section {
                timerCard(running)
                    .id(Self.timerRowID(running.itemId))
            }
        }
    }

    private func timerCard(_ running: RunningTimer) -> some View {
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
            // タイマーが2つ以上あるときは、少し小さくして画面に収まりやすくする
            .font(.system(size: timer.timers.count > 1 ? 30 : 40, weight: .semibold, design: .rounded).monospacedDigit())
            if running.priorSeconds > 0 {
                Text("前回までの記録 \(NowNext.durationText(Int(running.priorSeconds / 60))) をふくむ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // 1段目: 一時停止 / 再開(いちばん押しやすい大きなボタン)
            Button {
                togglePause(running.itemId)
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
                    stopTimer(running.itemId, markDone: true)
                } label: {
                    Label("完了", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    stopTimer(running.itemId, markDone: false)
                } label: {
                    Label("記録して終了", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
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
        updateFocusForTimers()
    }

    /// タイマー中の集中モード: 動いているタイマーが1つでもあればかけ、全部止まったら外す
    private func updateFocusForTimers() {
        // 勉強のタイマーだけを見る(食事などのタイマーでは集中モードにしない)
        let active = timer.activeTimers.filter { StudyKind.isStudy(subject: $0.subject, title: $0.title) }
        if active.isEmpty {
            screenTime.endForTimer()
        } else if focusDuringTimer && screenTime.isReady {
            // いちばん遅く終わる予定に合わせる
            screenTime.startForTimer(plannedEnd: active.compactMap(\.plannedEnd).max())
        }
    }

    /// その予定の、いちばん新しい記録(分)。画面のリストを優先し、無ければ渡された値を使う
    private func currentActualMinutes(of item: PlanItem) -> Int {
        let latest = store.items.first { $0.id == item.id }
            ?? store.upcomingItems(days: 0).first { $0.id == item.id }
            ?? item
        return latest.actualMinutes ?? 0
    }

    /// 一時停止 ⇄ 再開
    private func togglePause(_ itemId: UUID) {
        guard let running = timer.timer(for: itemId) else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if running.isPaused {
            timer.resume(itemId: itemId, now: Date())
        } else {
            // 一時停止までの区間を記録に残す
            store.recordSession(timer.pause(itemId: itemId, now: Date()))
            // 自動の集中モードは、一時停止を押したら終える(押したほうを優先)
            if StudyKind.isStudy(subject: running.subject, title: running.title) {
                screenTime.endAutoByUser()
            }
        }
        updateFocusForTimers()
        // ライブアクティビティも、止まった時間/続きの時間に出し直す
        if let updated = timer.timer(for: itemId) {
            showLiveActivity(for: updated)
        }
    }

    /// タイマーを止めて、勉強時間を記録する。
    /// reason: 記録に残す止めた理由(省略すると、完了なら done、そうでなければ stop)
    private func stopTimer(_ itemId: UUID, markDone: Bool, reason: String? = nil) {
        let stopped = timer.timer(for: itemId)
        guard let result = timer.stop(itemId: itemId, now: Date(), reason: reason ?? (markDone ? "done" : "stop")) else { return }
        store.recordSession(result.session)
        LiveActivityController.end(itemId: itemId)
        // 自分で「完了」「記録して終了」を押したら、自動の集中モードも終える(自動タイマーが止まったときは別)
        if reason != "auto", let stopped, StudyKind.isStudy(subject: stopped.subject, title: stopped.title) {
            screenTime.endAutoByUser()
        }
        updateFocusForTimers()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        store.recordStudy(itemId: result.itemId, minutes: result.minutes, markDone: markDone)
    }

    // MARK: - タイマーの共有(iPhone と iPad)

    /// タイマーをサーバーと合わせる(通信中に頼まれたら、終わってからもう一度)
    private func requestTimerSync() {
        guard network.isOnline else { return }
        if isSyncingTimers {
            timerSyncAgain = true
            return
        }
        isSyncingTimers = true
        Task { @MainActor in
            defer { isSyncingTimers = false }
            repeat {
                timerSyncAgain = false
                do {
                    let changes = try await TimerSync.sync(timer: timer, userId: userId, api: RemoteAPI())
                    applyTimerChanges(changes)
                } catch {
                    // 送れなかった変更は覚えてあるので、次の機会(30秒後・電波が戻ったとき)にまた送る
                    print("タイマーの共有に失敗: \(error)")
                    return
                }
            } while timerSyncAgain
        }
    }

    /// ほかの端末で始めた・変えた・止めたタイマーに合わせて、ライブアクティビティと集中モードを直す
    private func applyTimerChanges(_ changes: TimerRemoteChanges) {
        guard !changes.isEmpty else { return }
        for itemId in changes.removed {
            LiveActivityController.end(itemId: itemId)
        }
        for running in changes.changed {
            LiveActivityController.update(running)
        }
        for running in changes.added {
            showLiveActivity(for: running)
        }
        updateFocusForTimers()
    }

    /// ウィジェットでのチェックを取りこむ。勉強の予定を完了にしていたら、自動の集中モードを終える
    private func applyWidgetToggles() {
        let toggles = SharedStore.takePendingToggles()
        let studyIds = Set(store.items.filter(\.isStudy).map(\.id))
        if toggles.contains(where: { $0.done && studyIds.contains($0.itemId) }) {
            screenTime.endAutoByUser()
        }
        store.applyWidgetToggles(toggles)
    }

    /// ウィジェットのボタンで変わったタイマーを読み直し、止めた区間・勉強時間を記録に取りこむ
    private func applyWidgetTimerEvents() {
        let events = TimerWidgetActions.takeEvents()
        timer.reload()
        for event in events {
            store.recordSession(event.session)
            switch event.action {
            case .stop:
                LiveActivityController.end(itemId: event.itemId)
                store.recordStudy(itemId: event.itemId, minutes: event.minutes ?? 0, markDone: event.markDone)
                if let session = event.session, StudyKind.isStudy(subject: session.subject, title: session.title) {
                    screenTime.endAutoByUser()
                }
            case .pause, .resume:
                if let updated = timer.timer(for: event.itemId) {
                    LiveActivityController.update(updated)
                }
            }
        }
        updateFocusForTimers()
    }

    /// 自動タイマー: 予定の時間になったら始め、終了時刻を過ぎたら止める
    private func checkAutoTimer() {
        // 自動で始めたタイマーは、設定に関係なく終了時刻で止める
        for itemId in timer.itemIdsToAutoStop(now: Date()) {
            stopTimer(itemId, markDone: false, reason: "auto")
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
        for running in timer.timers where !LiveActivityController.isShowing(itemId: running.itemId) {
            showLiveActivity(for: running)
        }
    }

    // MARK: - カレンダー連携

    /// 今日から7日分の予定ブロックを「MyStudy」カレンダーに書き出す
    private func exportToCalendar() {
        guard calendarSyncEnabled else { return }
        let today = store.today
        let items = store.upcomingItems(days: 7)
        Task {
            // 睡眠の予定も読んで、カレンダーに「睡眠」として書き出す(アプリの画面には出さない)。
            // 昨夜の分(今朝まで)もふくめる
            let sleeps = await loadSleeps(fromNight: DayKey.adding(-1, to: today), toNight: DayKey.adding(7, to: today))
            CalendarSync.export(items: items, sleeps: sleeps, from: today, to: DayKey.adding(7, to: today))
        }
    }

    /// 睡眠の予定を読む。読めなければ端末に取っておいた分、それも無ければ nil(カレンダーの「睡眠」に手をつけない)
    private func loadSleeps(fromNight: String, toNight: String) async -> [SleepPlan]? {
        do {
            let sleeps = try await RemoteAPI().fetchSleeps(fromNight: fromNight, toNight: toNight)
            SleepCache.save(sleeps)
            return sleeps
        } catch {
            return SleepCache.load()?.filter { $0.night >= fromNight && $0.night <= toNight }
        }
    }

    private func loadCalendarEvents() {
        calendarEvents = calendarSyncEnabled ? CalendarSync.events(on: store.selectedDate) : []
        // カレンダーの予定が変わったかもしれないので、ウィジェットにも渡し直す
        if let lastWidgetSnapshot {
            publishWidget(lastWidgetSnapshot)
        }
    }

    /// ウィジェットにデータを渡す。カレンダー連携がオンなら、その日のカレンダーの予定(時間のあるもの)も足す。
    /// ウィジェットは、予定が無い時間の「今」にカレンダーの予定(例: 授業の「化学」)を出す
    private func publishWidget(_ snapshot: WidgetSnapshot) {
        var snapshot = snapshot
        if calendarSyncEnabled && CalendarSync.isAuthorized {
            for key in snapshot.days.keys {
                snapshot.days[key]?.events = CalendarSync.events(on: key)
                    .filter { !$0.isAllDay }
                    .map { WidgetCalendarEvent(title: $0.title, start: $0.start, end: $0.end) }
            }
        }
        WidgetBridge.publish(snapshot)
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
        // Claude からのひとこと(前日の反省への返事・その日の注意点など)
        if let note = store.day?.coachNote, !note.isEmpty {
            Section {
                Text(note)
                    .font(.subheadline)
                    .textSelection(.enabled)
            } header: {
                Label("Claude より", systemImage: "bubble.left.and.text.bubble.right")
            }
            .listRowBackground(Color.orange.opacity(0.10))
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
        } else if store.items.isEmpty && sleepItems.isEmpty && !store.hasPulledSelectedDate {
            // 端末にデータが無く、サーバーからも読めていない(オフラインなど)
            Section {
                ContentUnavailableView(
                    "まだ読みこめていません",
                    systemImage: "icloud.slash",
                    description: Text("電波がつながると、この日の予定を読みこみます。")
                )
            }
        } else if store.items.isEmpty && sleepItems.isEmpty {
            Section {
                ContentUnavailableView(
                    "予定がありません",
                    systemImage: "calendar.badge.plus",
                    description: Text("Claude に予定を作ってもらうと、ここに表示されます。")
                )
            }
        } else {
            let blocks = blocksWithSleep
            if !blocks.isEmpty {
                Section("予定") {
                    ForEach(blocks) { item in
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
            isTimerRunning: timer.timer(for: item.id) != nil
        )
        // 左へスワイプすると出るボタン
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // 睡眠の行は、ここでは直せない(Claude が sleep_plans で決める)
            if !item.isSleep {
            if store.canDelete(item) {
                Button("削除", systemImage: "trash", role: .destructive) {
                    store.deleteItem(item)
                }
            }
            Button("明日へ", systemImage: "arrow.turn.down.right") {
                store.moveToTomorrow(item)
            }
            .tint(.orange)
            Button("編集", systemImage: "pencil") {
                editingItem = item
            }
            .tint(.blue)
            }
        }
    }

    /// 長押しでタイマー開始。ほかのタイマーは止めずに、いっしょに動かす
    private func startTimerByLongPress(_ item: PlanItem) {
        // その予定のタイマーがもうあれば、新しく始めずに、そのタイマーまで移動するだけ
        if timer.timer(for: item.id) == nil {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            startTimer(for: item, isAuto: false)
        }
        scrollTargetItemId = item.id
        scrollToTimerRequest += 1   // 数字が変わると、上の onChange が動いてタイマーまで移動する
    }

    private func toggle(_ item: PlanItem) {
        // 睡眠はチェックしない(長押しでタイマーを使って、実際に寝た時間を測る)
        guard !item.isSleep else { return }
        // 勉強の予定を「完了」にしたら、自動の集中モードを終える(押したほうを優先。次の予定の時間にまた入る)
        if !item.done && item.isStudy {
            screenTime.endAutoByUser()
        }
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
