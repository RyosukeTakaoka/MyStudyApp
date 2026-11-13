import Foundation

/// タイマーの1区間(始めた/再開した時刻 〜 一時停止・終了した時刻)。study_sessions テーブルの1行
struct StudySession: Codable, Equatable, Sendable {
    /// アプリで決める id(送り直しても、サーバーで二重にならないように)
    let id: UUID
    let itemId: UUID
    /// その予定の日付("2026-11-13" の形。わからなければ nil)
    let itemDate: String?
    let title: String
    let subject: String
    let startedAt: Date
    let endedAt: Date
    /// 止めた理由: pause / stop / done / auto / switch
    let endReason: String

    enum CodingKeys: String, CodingKey {
        case id, title, subject
        case itemId = "item_id"
        case itemDate = "item_date"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case endReason = "end_reason"
    }

    /// サーバーに送るときの形。日時は、末尾に「Z」(世界標準時)を付けた文字にする
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let style = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        try c.encode(id, forKey: .id)
        try c.encode(itemId, forKey: .itemId)
        try c.encode(itemDate, forKey: .itemDate)
        try c.encode(title, forKey: .title)
        try c.encode(subject, forKey: .subject)
        try c.encode(startedAt.formatted(style), forKey: .startedAt)
        try c.encode(endedAt.formatted(style), forKey: .endedAt)
        try c.encode(endReason, forKey: .endReason)
    }

    init(id: UUID = UUID(), itemId: UUID, itemDate: String?, title: String, subject: String,
         startedAt: Date, endedAt: Date, endReason: String) {
        self.id = id
        self.itemId = itemId
        self.itemDate = itemDate
        self.title = title
        self.subject = subject
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.endReason = endReason
    }

    /// 端末に保存したものを読み直すとき(保存は上の encode と同じ形)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        itemId = try c.decode(UUID.self, forKey: .itemId)
        itemDate = try c.decodeIfPresent(String.self, forKey: .itemDate)
        title = try c.decode(String.self, forKey: .title)
        subject = try c.decode(String.self, forKey: .subject)
        let style = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        startedAt = try style.parse(c.decode(String.self, forKey: .startedAt))
        endedAt = try style.parse(c.decode(String.self, forKey: .endedAt))
        endReason = try c.decode(String.self, forKey: .endReason)
    }
}

/// まだサーバーに送っていないタイマーの記録をためておく場所(端末のファイル)
@MainActor
final class SessionQueue {
    private(set) var pending: [StudySession] = []
    private let fileURL: URL?

    init(fileURL: URL? = SessionQueue.defaultFileURL) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([StudySession].self, from: data) {
            pending = saved
        }
    }

    nonisolated static var defaultFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("study-sessions.json")
    }

    /// ログアウトしたときに消す
    nonisolated static func clearSaved() {
        if let url = defaultFileURL { try? FileManager.default.removeItem(at: url) }
    }

    func append(_ session: StudySession) {
        pending.append(session)
        save()
    }

    /// 送り終わったものを取りのぞく
    func remove(ids: Set<UUID>) {
        pending.removeAll { ids.contains($0.id) }
        save()
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(pending) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
