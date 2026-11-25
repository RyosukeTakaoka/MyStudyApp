import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import Observation

// 集中モード(スクリーンタイム)をアプリから操作する係。
@MainActor
@Observable
final class ScreenTimeController {
    /// スクリーンタイムの使用が許可されているか
    private(set) var isAuthorized = false
    /// 使ってよいアプリの選択
    var selection = FocusSelectionStore.load() {
        didSet {
            FocusSelectionStore.save(selection)
            FocusShield.sync()   // かかっている最中なら、新しい選択ですぐかけ直す
        }
    }
    private(set) var flags = FocusFlagsStore.load(AppGroup.defaults)
    var errorMessage: String?
    /// 自動の時間帯の登録に失敗したときの理由(設定画面に出す。うまくいけば nil)
    private(set) var registrationProblem: String?
    /// 登録してある自動の時間帯(設定画面に出す)
    private(set) var registeredBlocks: [FocusPlan.Window] = []

    private let center = DeviceActivityCenter()
    private static let scheduledKey = "focus.scheduledBlocks"

    init() {
        isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
    }

    var allowedAppCount: Int { selection.applicationTokens.count }
    /// 集中モードを使える状態か(許可済み・アプリを1つ以上選択済み)
    var isReady: Bool { isAuthorized && allowedAppCount > 0 }

    func isActive(now: Date = Date()) -> Bool { flags.shouldShield(now: now) }
    var activeUntil: Date? { isActive() ? flags.windowEnd : nil }

    // MARK: - 許可

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            errorMessage = nil
        } catch {
            errorMessage = """
            スクリーンタイムの許可を得られませんでした。
            iPhone の 設定 → スクリーンタイム がオンになっているか確かめて、もう一度ためしてください。

            \(error.localizedDescription)
            """
        }
        isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
        applyPermanentBlock()
    }

    // MARK: - 状態の読み直し

    /// アプリを開いたときなどに呼ぶ(拡張機能が記録を書きかえているかもしれないため)
    func refresh() {
        isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
        flags = FocusFlagsStore.load(AppGroup.defaults)
        // 終わりの時刻を過ぎていたら外す(拡張機能が動かなかったときの保険)。
        // まだ続いている自動の時間帯があれば、そちらに切りかえる
        if let end = flags.windowEnd, end <= Date() {
            flags.finish(name: flags.windowName, now: Date(), blocks: FocusBlockStore.load(AppGroup.defaults))
            save()
        }
        // 予定の時間になっているのに、まだかかっていなければかける
        // (時間の始まりに拡張機能が呼ばれなかったときの保険)
        beginCoveringBlockIfNeeded()
        registeredBlocks = FocusBlockStore.load(AppGroup.defaults).filter { $0.end > Date() }
        FocusShield.sync()
        applyPermanentBlock()
    }

    /// 今の時刻をふくむ自動の時間帯があり、まだかかっていなければかける(自動がオンのときだけ)
    private func beginCoveringBlockIfNeeded(now: Date = Date()) {
        guard isReady, UserDefaults.standard.object(forKey: AppSettings.focusAutoBlocksKey) as? Bool ?? true else { return }
        if flags.beginCoveringBlock(now: now, blocks: FocusBlockStore.load(AppGroup.defaults)) {
            save()
        }
    }

    // MARK: - 常時ブロック(365日24時間。アプリの中に外すボタンは置かない)

    /// 常時ブロックをかけ直し、2027/1/1 にニコニコ動画を足す合図を登録する
    func applyPermanentBlock(now: Date = Date()) {
        guard isAuthorized else { return }
        PermanentBlock.apply(now: now)
        // 1月1日 0:00 に、アプリを閉じていても拡張機能がニコニコ動画を足せるように登録する
        let today = DayKey.today(now: now)
        guard today < PermanentBlockList.niconicoStartDay,
              let start = DayKey.date(dayKey: PermanentBlockList.niconicoStartDay, minutes: 0)
        else { return }
        let name = DeviceActivityName(PermanentBlockList.niconicoActivityName)
        guard !center.activities.contains(name) else { return }
        try? center.startMonitoring(name, during: Self.schedule(start: start, end: start.addingTimeInterval(20 * 60)))
    }

    /// 常時ブロックするアプリを足す(外すことはできない)
    func addPermanentApps(_ selection: FamilyActivitySelection) {
        PermanentBlockStore.addApps(selection)
        applyPermanentBlock()
    }

    /// 2027/1/1 から止めるアプリ(ニコニコ動画)を足す
    func addNiconicoApps(_ selection: FamilyActivitySelection) {
        PermanentBlockStore.addNiconicoApps(selection)
        applyPermanentBlock()
    }

    /// 止めるサイトを自分で足す(足すだけで、外せない)。足せたら true
    @discardableResult
    func addPermanentDomain(_ input: String) -> Bool {
        guard let host = PermanentBlockList.customHost(from: input) else { return false }
        PermanentBlockStore.addCustomDomain(host)
        applyPermanentBlock()
        return true
    }

    /// 今止めているサイトの一覧(50件まで)
    var permanentDomains: [String] {
        PermanentBlockList.domains(today: DayKey.today(now: Date()), invidious: PermanentBlockStore.invidiousHosts,
                                   custom: PermanentBlockStore.customDomains)
    }

    var permanentAppCount: Int { PermanentBlockStore.apps().applicationTokens.count }
    var niconicoAppCount: Int { PermanentBlockStore.niconicoApps().applicationTokens.count }

    /// Invidious の公開ホストの一覧を読み直す(1週間に1回まで)。読めなければ前の一覧のまま
    func updateInvidiousList(now: Date = Date()) async {
        if let last = PermanentBlockStore.invidiousUpdatedAt, now.timeIntervalSince(last) < 7 * 24 * 3600 { return }
        guard let url = URL(string: "https://api.invidious.io/instances.json?sort_by=type,users"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return }
        let hosts = PermanentBlockList.parseInvidiousInstances(data)
        guard !hosts.isEmpty else { return }
        PermanentBlockStore.saveInvidious(hosts, at: now)
        applyPermanentBlock(now: now)
    }

    // MARK: - 手動・タイマー

    /// 今すぐ集中モード(minutes 分)
    func startManual(minutes: Int) {
        let now = Date()
        startWindow(kind: "manual", end: now.addingTimeInterval(TimeInterval(minutes * 60)), now: now)
    }

    /// タイマーを始めたとき
    func startForTimer(plannedEnd: Date?) {
        let now = Date()
        startWindow(kind: "timer", end: FocusPlan.timerWindowEnd(plannedEnd: plannedEnd, now: now), now: now)
    }

    /// タイマーを止めたとき(タイマーでかけた集中モードだけを終える)
    /// 予定の時間の集中モード(自動)がまだ続いていれば、そちらに切りかえる
    func endForTimer() {
        guard let name = flags.windowName, FocusPlan.kind(fromName: name) == "timer" else { return }
        center.stopMonitoring([DeviceActivityName(name)])
        flags.finish(name: name, now: Date(), blocks: FocusBlockStore.load(AppGroup.defaults))
        save()
        FocusShield.sync()
    }

    /// 今かかっている集中モードを、今すぐ終える
    func endNow() {
        if let name = flags.windowName {
            center.stopMonitoring([DeviceActivityName(name)])
            if FocusPlan.kind(fromName: name) == "block" {
                flags.dismissed.append(name)
            }
        }
        // 自分で終えたので、今の時刻をふくむ自動の時間帯にも、もう戻らないようにする
        let now = Date()
        for window in FocusBlockStore.load(AppGroup.defaults)
        where window.start <= now && now < window.end && !flags.dismissed.contains(window.name) {
            flags.dismissed.append(window.name)
        }
        flags.windowEnd = nil
        flags.windowName = nil
        save()
        FocusShield.sync()
    }

    private func startWindow(kind: String, end: Date, now: Date) {
        guard isReady else {
            errorMessage = "先に「スクリーンタイムの許可」と「使ってよいアプリ」の選択をしてください。"
            return
        }
        let name = FocusPlan.name(kind: kind, end: end, id: String(UUID().uuidString.prefix(8)))
        let old = flags.windowName
        // 今かかっている時間帯(予定の時間の自動など)のほうが長く続くなら、そのまま(置きかえない)
        guard flags.begin(name: name, end: end, now: now) else {
            errorMessage = nil
            return
        }
        // 前の手動・タイマーの監視は止める(予定ブロックの監視は残す)
        if let old, FocusPlan.kind(fromName: old) != "block" {
            center.stopMonitoring([DeviceActivityName(old)])
        }
        save()
        FocusShield.sync()   // すぐに制限をかける

        // 終わりの時刻に、アプリを閉じていても拡張機能が制限を外せるように登録する
        do {
            try center.startMonitoring(DeviceActivityName(name), during: Self.schedule(start: now, end: end))
            errorMessage = nil
        } catch {
            errorMessage = "終わりの時刻の自動解除を登録できませんでした。アプリを開いて「今すぐ終える」で解除してください。\n\(error.localizedDescription)"
        }
    }

    // MARK: - 予定ブロックの自動の集中モード

    /// 予定に合わせて、自動の集中モードを登録しなおす(同期のたびに呼ぶ)
    func rescheduleBlocks(items: [PlanItem], enabled: Bool) {
        let now = Date()
        flags.dismissed = flags.dismissed.filter { (FocusPlan.endDate(fromName: $0) ?? .distantPast) > now }
        let windows = (enabled && isReady)
            ? FocusPlan.blockWindows(items: items, now: now, dismissed: flags.dismissed)
            : []
        let newNames = windows.map(\.name)
        let oldNames = AppGroup.defaults.stringArray(forKey: Self.scheduledKey) ?? []

        // なくなったものは止め、増えたものだけ登録する(登録済みのものはそのまま)
        let removed = oldNames.filter { !newNames.contains($0) }
        center.stopMonitoring(removed.map { DeviceActivityName($0) })
        var registered = oldNames.filter { newNames.contains($0) }
        var problems: [String] = []
        for window in windows where !oldNames.contains(window.name) {
            do {
                try center.startMonitoring(DeviceActivityName(window.name), during: Self.schedule(start: window.start, end: window.end))
                registered.append(window.name)
            } catch {
                let range = "\(window.start.formatted(date: .omitted, time: .shortened))〜\(window.end.formatted(date: .omitted, time: .shortened))"
                problems.append("\(range): \(error.localizedDescription)")
            }
        }
        registrationProblem = problems.isEmpty ? nil : "自動の時間帯を登録できませんでした。\n" + problems.joined(separator: "\n")
        AppGroup.defaults.set(registered, forKey: Self.scheduledKey)
        // 重なったときの切りかえ用に、登録できた時間帯を覚えておく(拡張機能も読む)
        let registeredWindows = windows.filter { registered.contains($0.name) }
        FocusBlockStore.save(registeredWindows, AppGroup.defaults)

        // 予定がチェックされたり消されたりして、かかっている予定ブロックの集中モードが不要になったら外す
        // (ほかに今かかるべき自動の時間帯があれば、そちらに切りかえる)
        if let active = flags.windowName, FocusPlan.kind(fromName: active) == "block", !newNames.contains(active) {
            flags.finish(name: active, now: now, blocks: registeredWindows)
        }
        // すでに始まっている時間帯は、iPhone が「始まり」を知らせてくれないことがあるので、ここでかける
        if enabled && isReady {
            flags.beginCoveringBlock(now: now, blocks: registeredWindows)
        }
        registeredBlocks = registeredWindows.filter { $0.end > now }
        save()
        FocusShield.sync()
    }

    // MARK: - ログアウト

    /// 全部の集中モードを止めて、記録を消す
    static func resetAll() {
        DeviceActivityCenter().stopMonitoring()
        FocusFlagsStore.save(FocusFlags(), AppGroup.defaults)
        AppGroup.defaults.removeObject(forKey: scheduledKey)
        FocusBlockStore.save([], AppGroup.defaults)
        FocusShield.clear()
    }

    // MARK: - 中で使う道具

    private func save() {
        FocusFlagsStore.save(flags, AppGroup.defaults)
    }

    private static func schedule(start: Date, end: Date) -> DeviceActivitySchedule {
        let calendar = DayKey.gregorian()
        let parts: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        return DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(parts, from: start),
            intervalEnd: calendar.dateComponents(parts, from: end),
            repeats: false
        )
    }
}
