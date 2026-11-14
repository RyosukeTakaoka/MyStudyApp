import Foundation

// サーバーとの読み書きの「約束ごと」。
// 本物は RemoteAPI(Supabase と通信)です。テストでは、通信しないニセモノに差しかえます。
protocol PlanAPI: Sendable {
    func fetchItems(from: String, to: String) async throws -> [PlanItem]
    func fetchDays(from: String, to: String) async throws -> [DayInfo]
    func updateProgress(id: UUID, done: Bool, doneAt: Date?, actualMinutes: Int?) async throws
    func saveReflection(userId: UUID, date: String, reflection: String) async throws
    /// タイマーの記録を送る(同じ id がすでにあれば何もしない)
    func insertSessions(_ sessions: [StudySession]) async throws
    /// アプリで足した・直した予定を送る(id が同じ行があれば上書き)
    func upsertItems(_ items: [PlanItem]) async throws
    /// アプリで消した予定を消す
    func deleteItems(ids: [UUID]) async throws
}

// RemoteAPI は、すでに上の4つの関数を持っているので、そのまま約束を満たす
extension RemoteAPI: PlanAPI {}
