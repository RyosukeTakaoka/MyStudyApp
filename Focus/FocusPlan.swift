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

// 時間帯が重なったときの決まり(例: 自動の集中モード 13:20〜19:00 の途中で、タイマーを始めた)
//   ・新しい時間帯は、今の時間帯より長く続くときだけ置きかえる(短いほうに置きかえて、早く外れないように)
//   ・時間帯が終わった・止めたときは、まだ続いている自動の時間帯があれば、そちらに切りかえる
//     (タイマーを止めても、予定の時間の集中モードは続く)
extension FocusFlags {
    /// 新しい時間帯を始める。今かかっている時間帯のほうが長く続くなら、そのまま(false を返す)
    @discardableResult
    mutating func begin(name: String, end: Date, now: Date) -> Bool {
        if let current = windowEnd, windowName != nil, current > now, current >= end {
            return false
        }
        windowEnd = end
        windowName = name
        return true
    }

    /// 時間帯 name が終わった(止めた)とき。今かかっているのが別の時間帯なら、何もしない。
    /// 外したあと、まだ続いている自動の時間帯(blocks)があれば、いちばん長く続くものに切りかえる
    mutating func finish(name: String?, now: Date, blocks: [FocusPlan.Window]) {
        guard name == nil || windowName == name else { return }
        windowEnd = nil
        windowName = nil
        let covering = blocks.filter { block in
            block.name != name && block.canBegin(at: now) && !dismissed.contains(block.name)
        }
        if let next = covering.max(by: { $0.end < $1.end }) {
            windowEnd = next.end
            windowName = next.name
        }
    }

    /// 自分で「完了・一時停止・記録して終了」を押したとき: 今かかっている自動の集中モードを終える。
    /// 今の時刻をふくむ自動の時間帯も、もうかけ直さない(次の予定の時間になれば、また入る)
    mutating func endBlocksByUser(now: Date, blocks: [FocusPlan.Window]) {
        for block in blocks where block.start <= now && now < block.end && !dismissed.contains(block.name) {
            dismissed.append(block.name)
        }
        if let active = windowName, FocusPlan.kind(fromName: active) == "block" {
            if !dismissed.contains(active) { dismissed.append(active) }
            windowEnd = nil
            windowName = nil
        }
    }
}

extension FocusFlags {
    /// 今かかっていなければ、今の時刻をふくむ自動の時間帯(blocks)をかける。かけたら true。
    /// (拡張機能が時間の始まりに呼ばれなかったときの保険。アプリを開いたとき・開いているあいだに使う)
    @discardableResult
    mutating func beginCoveringBlock(now: Date, blocks: [FocusPlan.Window]) -> Bool {
        guard !shouldShield(now: now) else { return false }
        let covering = blocks.filter { $0.canBegin(at: now) && !dismissed.contains($0.name) }
        guard let window = covering.max(by: { $0.end < $1.end }) else { return false }
        windowEnd = window.end
        windowName = window.name
        return true
    }
}

/// 登録した自動の時間帯の一覧(アプリと拡張機能の両方が読む。重なったときの切りかえに使う)
enum FocusBlockStore {
    private static let key = "focus.blockWindows"

    static func load(_ defaults: UserDefaults) -> [FocusPlan.Window] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([FocusPlan.Window].self, from: data)) ?? []
    }

    static func save(_ windows: [FocusPlan.Window], _ defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(windows) {
            defaults.set(data, forKey: key)
        }
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

    struct Window: Codable, Equatable {
        let name: String
        let start: Date
        /// 時間帯の終わり(自動の時間帯は、その日の 23:59。押し忘れても、ここで必ず外れる)
        let end: Date
        /// 予定の終わりの時刻(自動の時間帯だけ)。アプリが「かけ直す」のは、この時刻まで
        var plannedEnd: Date? = nil

        /// アプリが新しくかけてよい時刻か(始まり〜予定の終わり)
        func canBegin(at now: Date) -> Bool {
            start <= now && now < (plannedEnd ?? end)
        }
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

    /// 予定ブロックから、自動で集中モードにする時間帯を作る(予定1つにつき1つ)。
    ///   ・未チェック・勉強の予定・終わりの時刻がある・まだ予定の終わりが来ていないブロックだけ
    ///   ・始まりは予定の開始(すでに始まっていれば今)。終わりは、その日の 23:59
    ///     (予定の終わりの時刻を過ぎても、自分で完了・一時停止などを押すまで続くように。押し忘れても 23:59 で必ず外れる)
    ///   ・近いものから maxBlockWindows 個まで
    static func blockWindows(
        items: [PlanItem],
        now: Date,
        dismissed: [String] = [],
        calendar: Calendar = DayKey.gregorian()
    ) -> [Window] {
        let windows: [Window] = items.compactMap { item in
            // 食事・睡眠・移動などの生活の予定では、集中モードにしない
            guard item.isBlock, !item.done, item.isStudy,
                  let startMinutes = item.startMinutes, let endMinutes = item.endMinutes,
                  let start = DayKey.date(dayKey: item.date, minutes: startMinutes, calendar: calendar),
                  let plannedEnd = DayKey.date(dayKey: item.date, minutes: endMinutes, calendar: calendar),
                  let dayEnd = DayKey.date(dayKey: item.date, minutes: 23 * 60 + 59, calendar: calendar),
                  plannedEnd > start, plannedEnd > now, dayEnd > now
            else { return nil }
            let name = Self.name(kind: "block", end: dayEnd, id: String(item.id.uuidString.prefix(8)))
            guard !dismissed.contains(name) else { return nil }
            var begin = max(start, now)
            // スクリーンタイムの決まりで、時間帯は15分以上(夜遅い予定は、始まりを少し前にする)
            if dayEnd.timeIntervalSince(begin) < minimumSeconds {
                begin = dayEnd.addingTimeInterval(-minimumSeconds)
            }
            return Window(name: name, start: begin, end: dayEnd, plannedEnd: plannedEnd)
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
