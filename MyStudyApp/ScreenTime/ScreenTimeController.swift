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
            TestFlight から入れた版では、Apple の許可が下りるまでこの機能は使えません(Xcode から入れた版では使えます)。

            \(error.localizedDescription)
            """
        }
        isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
    }

    // MARK: - 状態の読み直し

    /// アプリを開いたときなどに呼ぶ(拡張機能が記録を書きかえているかもしれないため)
    func refresh() {
        isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
        flags = FocusFlagsStore.load(AppGroup.defaults)
        // 終わりの時刻を過ぎていたら記録を消す(拡張機能が動かなかったときの保険)
        if let end = flags.windowEnd, end <= Date() {
            flags.windowEnd = nil
            flags.windowName = nil
            save()
        }
        FocusShield.sync()
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
    func endForTimer() {
        guard let name = flags.windowName, FocusPlan.kind(fromName: name) == "timer" else { return }
        endNow()
    }

    /// 今かかっている集中モードを、今すぐ終える
    func endNow() {
        if let name = flags.windowName {
            center.stopMonitoring([DeviceActivityName(name)])
            if FocusPlan.kind(fromName: name) == "block" {
                flags.dismissed.append(name)
            }
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
        // 前の手動・タイマーの監視は止める(予定ブロックの監視は残す)
        if let old = flags.windowName, FocusPlan.kind(fromName: old) != "block" {
            center.stopMonitoring([DeviceActivityName(old)])
        }
        let name = FocusPlan.name(kind: kind, end: end, id: String(UUID().uuidString.prefix(8)))
        flags.windowEnd = end
        flags.windowName = name
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
        for window in windows where !oldNames.contains(window.name) {
            do {
                try center.startMonitoring(DeviceActivityName(window.name), during: Self.schedule(start: window.start, end: window.end))
                registered.append(window.name)
            } catch {
                print("集中モードの登録に失敗: \(window.name) \(error)")
            }
        }
        AppGroup.defaults.set(registered, forKey: Self.scheduledKey)

        // 予定がチェックされたり消されたりして、かかっている予定ブロックの集中モードが不要になったら外す
        if let active = flags.windowName, FocusPlan.kind(fromName: active) == "block", !newNames.contains(active) {
            flags.windowEnd = nil
            flags.windowName = nil
        }
        save()
        FocusShield.sync()
    }

    // MARK: - ログアウト

    /// 全部の集中モードを止めて、記録を消す
    static func resetAll() {
        DeviceActivityCenter().stopMonitoring()
        FocusFlagsStore.save(FocusFlags(), AppGroup.defaults)
        AppGroup.defaults.removeObject(forKey: scheduledKey)
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
