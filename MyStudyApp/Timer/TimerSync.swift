import Foundation

// 動いているタイマーを、サーバー(running_timers)を通して iPhone と iPad で共有する係。
//   1. この端末で変えたタイマー(始めた・一時停止・再開・終了)をサーバーへ送る
//   2. サーバーのタイマーを読んで、ほかの端末で始めた・止めたタイマーを取りこむ
// 電波が無くて送れなかった変更は覚えておき、次に送る。

/// サーバーとのやりとり(テストでは偽物に差しかえる)
protocol RunningTimerAPI: Sendable {
    func fetchRunningTimers() async throws -> [RunningTimer]
    func upsertRunningTimer(_ timer: RunningTimer, userId: UUID) async throws
    func deleteRunningTimer(itemId: UUID) async throws
}

@MainActor
enum TimerSync {
    static func sync(timer: StudyTimer, userId: UUID, api: RunningTimerAPI) async throws -> TimerRemoteChanges {
        // 1. 送る(送っているあいだにまた変えたら、印は残してもう一度送る)
        for itemId in timer.dirtyItemIds {
            guard let stamp = timer.dirtyStamp(itemId) else { continue }
            if let running = timer.timer(for: itemId) {
                try await api.upsertRunningTimer(running, userId: userId)
            } else {
                try await api.deleteRunningTimer(itemId: itemId)
            }
            timer.clearDirty(itemId, ifUnchangedSince: stamp)
        }
        // 2. 読む
        let remote = try await api.fetchRunningTimers()
        return timer.applyRemote(remote)
    }
}

/// running_timers テーブルの1行(サーバーとやりとりする形)
struct RunningTimerRow: Codable, Equatable {
    var userId: UUID?
    var itemId: UUID
    var itemDate: String?
    var title: String
    var subject: String
    var startedAt: Date
    var accumulatedSeconds: Double
    var pausedAt: Date?
    var priorSeconds: Double
    var plannedEnd: Date?
    var isAuto: Bool

    enum CodingKeys: String, CodingKey {
        case title, subject
        case userId = "user_id"
        case itemId = "item_id"
        case itemDate = "item_date"
        case startedAt = "started_at"
        case accumulatedSeconds = "accumulated_seconds"
        case pausedAt = "paused_at"
        case priorSeconds = "prior_seconds"
        case plannedEnd = "planned_end"
        case isAuto = "is_auto"
    }

    init(timer: RunningTimer, userId: UUID) {
        self.userId = userId
        itemId = timer.itemId
        itemDate = timer.itemDate
        title = timer.title
        subject = timer.subject
        startedAt = timer.startedAt
        accumulatedSeconds = timer.accumulatedSeconds
        pausedAt = timer.pausedAt
        priorSeconds = timer.priorSeconds
        plannedEnd = timer.plannedEnd
        isAuto = timer.isAuto
    }

    var timer: RunningTimer {
        RunningTimer(itemId: itemId, title: title, subject: subject, startedAt: startedAt, plannedEnd: plannedEnd,
                     isAuto: isAuto, accumulatedSeconds: accumulatedSeconds, pausedAt: pausedAt,
                     priorSeconds: priorSeconds, itemDate: itemDate)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decodeIfPresent(UUID.self, forKey: .userId)
        itemId = try c.decode(UUID.self, forKey: .itemId)
        itemDate = try c.decodeIfPresent(String.self, forKey: .itemDate)
        title = try c.decode(String.self, forKey: .title)
        subject = try c.decodeIfPresent(String.self, forKey: .subject) ?? "その他"
        startedAt = try StudySession.parseDate(c.decode(String.self, forKey: .startedAt))
        accumulatedSeconds = try c.decodeIfPresent(Double.self, forKey: .accumulatedSeconds) ?? 0
        pausedAt = try c.decodeIfPresent(String.self, forKey: .pausedAt).map(StudySession.parseDate)
        priorSeconds = try c.decodeIfPresent(Double.self, forKey: .priorSeconds) ?? 0
        plannedEnd = try c.decodeIfPresent(String.self, forKey: .plannedEnd).map(StudySession.parseDate)
        isAuto = try c.decodeIfPresent(Bool.self, forKey: .isAuto) ?? false
    }

    /// 日時は、末尾に「Z」(世界標準時)を付けた文字で送る
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let style = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        try c.encodeIfPresent(userId, forKey: .userId)
        try c.encode(itemId, forKey: .itemId)
        try c.encode(itemDate, forKey: .itemDate)
        try c.encode(title, forKey: .title)
        try c.encode(subject, forKey: .subject)
        try c.encode(startedAt.formatted(style), forKey: .startedAt)
        try c.encode(accumulatedSeconds, forKey: .accumulatedSeconds)
        try c.encode(pausedAt?.formatted(style), forKey: .pausedAt)
        try c.encode(priorSeconds, forKey: .priorSeconds)
        try c.encode(plannedEnd?.formatted(style), forKey: .plannedEnd)
        try c.encode(isAuto, forKey: .isAuto)
    }
}

extension RemoteAPI: RunningTimerAPI {
    func fetchRunningTimers() async throws -> [RunningTimer] {
        let rows: [RunningTimerRow] = try await supabase
            .from("running_timers")
            .select()
            .execute()
            .value
        return rows.map(\.timer)
    }

    func upsertRunningTimer(_ timer: RunningTimer, userId: UUID) async throws {
        try await supabase
            .from("running_timers")
            // 同じ予定の行があれば上書きする
            .upsert(RunningTimerRow(timer: timer, userId: userId), onConflict: "user_id,item_id", returning: .minimal)
            .execute()
    }

    func deleteRunningTimer(itemId: UUID) async throws {
        try await supabase
            .from("running_timers")
            .delete(returning: .minimal)
            .eq("item_id", value: itemId)
            .execute()
    }
}
