import Foundation
import Observation

/// 資料の読み書き(本物は RemoteAPI。テストではニセモノに差しかえる)
protocol NotesAPI: Sendable {
    func fetchNotes() async throws -> [Note]
    func updateNoteBody(id: UUID, bodyMd: String) async throws
}

/// 一覧の見出し1つぶん(ピン留め・カテゴリ)
struct NoteSection: Equatable, Identifiable {
    var title: String
    var notes: [Note]
    var id: String { title }
}

/// 端末に保存しておく中身
struct NotesCache: Codable, Equatable {
    var notes: [Note] = []
    /// まだサーバーに送っていない本文(チェックを押したもの)。id → 本文
    var pending: [UUID: String] = [:]
}

// 「資料」タブのデータを持つ場所。端末に保存した内容を表示し、裏でサーバーと同期します。
@MainActor
@Observable
final class NotesStore {
    private(set) var notes: [Note] = []
    private(set) var isSyncing = false
    private(set) var hasLoadedOnce = false
    private(set) var problem: String?

    private var cache: NotesCache
    private let api: NotesAPI
    private let fileURL: URL?
    private var syncAgain = false

    init(api: NotesAPI? = nil, fileURL: URL? = NotesStore.defaultFileURL) {
        self.api = api ?? RemoteAPI()
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode(NotesCache.self, from: data) {
            cache = saved
            hasLoadedOnce = true
        } else {
            cache = NotesCache()
        }
        notes = cache.notes
    }

    nonisolated static var defaultFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("notes.json")
    }

    nonisolated static func clearSaved() {
        if let url = defaultFileURL { try? FileManager.default.removeItem(at: url) }
    }

    func note(id: UUID) -> Note? { notes.first { $0.id == id } }

    /// 一覧に出す順: ピン留め → カテゴリごと(並び順 → 題名)
    var sections: [NoteSection] {
        let sorted = notes.sorted { ($0.sortOrder, $0.title) < ($1.sortOrder, $1.title) }
        var result: [NoteSection] = []
        let pinned = sorted.filter(\.pinned)
        if !pinned.isEmpty { result.append(NoteSection(title: "ピン留め", notes: pinned)) }
        var categories: [String] = []
        for note in sorted where !note.pinned && !categories.contains(note.category) {
            categories.append(note.category)
        }
        for category in categories.sorted() {
            result.append(NoteSection(title: category, notes: sorted.filter { !$0.pinned && $0.category == category }))
        }
        return result
    }

    /// 本文の中のチェックを押したとき
    func toggleCheck(noteId: UUID, line: Int) {
        guard let index = cache.notes.firstIndex(where: { $0.id == noteId }) else { return }
        let body = NoteMarkdown.toggleCheck(in: cache.notes[index].bodyMd, line: line)
        guard body != cache.notes[index].bodyMd else { return }
        cache.notes[index].bodyMd = body
        cache.pending[noteId] = body
        save()
        notes = cache.notes
        Task { await sync() }
    }

    /// サーバーと同期する(送る → 受け取る)
    func sync() async {
        if isSyncing {
            syncAgain = true
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        repeat {
            syncAgain = false
            await syncOnce()
        } while syncAgain
    }

    private func syncOnce() async {
        for (id, body) in cache.pending {
            do {
                try await api.updateNoteBody(id: id, bodyMd: body)
                if cache.pending[id] == body { cache.pending[id] = nil }
            } catch {
                problem = Self.describe(error)
                save()
                return
            }
        }
        do {
            let fetched = try await api.fetchNotes()
            // まだ送っていない本文は、端末側を優先する
            cache.notes = fetched.map { note in
                var note = note
                if let mine = cache.pending[note.id] { note.bodyMd = mine }
                return note
            }
            let ids = Set(fetched.map(\.id))
            cache.pending = cache.pending.filter { ids.contains($0.key) }
            problem = nil
            hasLoadedOnce = true
        } catch {
            problem = Self.describe(error)
        }
        save()
        notes = cache.notes
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(cache) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func describe(_ error: Error) -> String {
        if ErrorText.isNetworkError(error) {
            return "オフラインです。端末に保存してある資料を表示しています。"
        }
        return "同期できませんでした。\n\(ErrorText.message(for: error))"
    }
}
