import Foundation

// 集中モード(スクリーンタイムで、選んだアプリ以外を制限する)の「時間の決まり」。
//
// 集中モードは、いつも「始まりと終わりが決まった時間帯(ウィンドウ)」として扱います。
//   ・block  … 予定ブロックの時間に自動でかかる
//   ・timer  … タイマー中にかかる
//   ・manual … 「今すぐ集中モード」でかかる
// 終わりの時刻を必ず決めておくことで、アプリを開けなくなっても、時間が来れば必ず解除されます。

/// いま集中モードがかかっているかの記録。アプリと監視用の拡張機能の両方が読み書きします。
struct FocusFlags: Codable, Equatable {
    /// いまかかっている集中モードの終わりの時刻(かかっていなければ nil)
    var windowEnd: Date?
    /// いまかかっている集中モードの名前
    var windowName: String?
    /// 自分で途中で終えた予定ブロックの名前(同じ予定で、もう一度かからないように)
    var dismissed: [String] = []

    func shouldShield(now: Date) -> Bool {
        guard let windowEnd else { return false }
        return windowEnd > now
    }
}

/// FocusFlags の保存場所(App Group の UserDefaults)
enum FocusFlagsStore {
    private static let key = "focus.flags"

    static func load(_ defaults: UserDefaults) -> FocusFlags {
        guard let data = defaults.data(forKey: key),
              let flags = try? JSONDecoder().decode(FocusFlags.self, from: data)
        else { return FocusFlags() }
        return flags
    }

    static func save(_ flags: FocusFlags, _ defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(flags) {
            defaults.set(data, forKey: key)
        }
    }
}

enum FocusPlan {
    /// スクリーンタイムの決まりで、自動の時間帯は15分以上でないと登録できない
    static let minimumSeconds: TimeInterval = 15 * 60
    /// 一度に登録できる数には上限(20)があるので、余裕をもって少なめにする
    static let maxBlockWindows = 15

    struct Window: Equatable {
        let name: String
        let start: Date
        let end: Date
    }

    /// 名前の形: "focus.<種類>.<終わりの時刻(秒)>.<id>"(拡張機能は名前から終わりの時刻を読む)
    static func name(kind: String, end: Date, id: String) -> String {
        "focus.\(kind).\(Int(end.timeIntervalSince1970)).\(id)"
    }

    static func kind(fromName name: String) -> String? {
        let parts = name.split(separator: ".")
        return parts.count >= 4 && parts[0] == "focus" ? String(parts[1]) : nil
    }

    static func endDate(fromName name: String) -> Date? {
        let parts = name.split(separator: ".")
        guard parts.count >= 4, parts[0] == "focus", let seconds = Int(parts[2]) else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    /// 予定ブロックから、自動で集中モードにする時間帯を作る。
    /// 未チェック・これから終わる・15分以上のブロックだけ。すでに始まっているものは「今から」にする
    static func blockWindows(
        items: [PlanItem],
        now: Date,
        dismissed: [String] = [],
        calendar: Calendar = DayKey.gregorian()
    ) -> [Window] {
        let windows: [Window] = items.compactMap { item in
            guard item.isBlock, !item.done,
                  let startMinutes = item.startMinutes, let endMinutes = item.endMinutes,
                  let start = DayKey.date(dayKey: item.date, minutes: startMinutes, calendar: calendar),
                  let end = DayKey.date(dayKey: item.date, minutes: endMinutes, calendar: calendar),
                  end > now
            else { return nil }
            let name = Self.name(kind: "block", end: end, id: String(item.id.uuidString.prefix(8)))
            guard !dismissed.contains(name) else { return nil }
            let effectiveStart = max(start, now)
            guard end.timeIntervalSince(effectiveStart) >= minimumSeconds else { return nil }
            return Window(name: name, start: effectiveStart, end: end)
        }
        return Array(windows.sorted { $0.start < $1.start }.prefix(maxBlockWindows))
    }

    /// タイマー中の集中モードの終わりの時刻。
    /// 予定の終了時刻があればそこまで(短すぎれば1時間)、最長3時間
    static func timerWindowEnd(plannedEnd: Date?, now: Date) -> Date {
        var end = now.addingTimeInterval(60 * 60)
        if let plannedEnd, plannedEnd.timeIntervalSince(now) >= minimumSeconds {
            end = plannedEnd
        }
        return min(end, now.addingTimeInterval(3 * 60 * 60))
    }
}
