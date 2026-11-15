import SwiftUI
import UIKit

// 「資料」タブ: Claude が書いた読み物(ルール・方針・答練の振り返りなど)の一覧。
struct NotesScreen: View {
    @State private var store = NotesStore()
    @State private var searchText = ""
    @Environment(\.scenePhase) private var scenePhase

    /// 画面の横幅の種類(iPad の広い画面だと .regular)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// iPad で右側に表示している資料
    @State private var selectedNoteId: UUID?

    var body: some View {
        if horizontalSizeClass == .regular {
            // iPad: 左に一覧、右に本文(「メモ」アプリのような2列の画面)
            NavigationSplitView {
                // selection: 一覧で押した資料の id が selectedNoteId に入る
                decorated(List(selection: $selectedNoteId) { listContent })
            } detail: {
                if let id = selectedNoteId {
                    NoteDetailScreen(store: store, noteId: id)
                        .id(id)   // 資料を切りかえたら、表示を作り直す(前の資料のスクロール位置を引きずらない)
                } else {
                    ContentUnavailableView("資料を選んでください", systemImage: "doc.text",
                                           description: Text("左の一覧から読みたい資料を押してください。"))
                }
            }
        } else {
            // iPhone: 一覧から押すと、本文の画面に進む
            NavigationStack {
                decorated(List { listContent })
                    .navigationDestination(for: UUID.self) { id in
                        NoteDetailScreen(store: store, noteId: id)
                    }
            }
        }
    }

    /// 一覧の中身(iPhone と iPad で共通)
    @ViewBuilder
    private var listContent: some View {
        if let problem = store.problem {
            Section {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        if !store.hasLoadedOnce {
            HStack {
                Spacer()
                ProgressView("読み込み中…")
                Spacer()
            }
        } else if store.notes.isEmpty {
            ContentUnavailableView(
                "資料がありません",
                systemImage: "doc.text",
                description: Text("Claude に資料ページを作ってもらうと、ここに表示されます。")
            )
        }
        ForEach(filteredSections) { section in
            Section(section.title) {
                ForEach(section.notes) { note in
                    NavigationLink(value: note.id) {
                        NoteRow(note: note)
                    }
                }
            }
        }
    }

    /// 一覧につける共通の設定(題名・検索・引っぱって更新・同期)
    private func decorated(_ list: some View) -> some View {
        list
            .navigationTitle("資料")
            // 題名と本文から探せる
            .searchable(text: $searchText, prompt: "資料を検索")
            .refreshable { await store.sync() }
            .task { await store.sync() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await store.sync() } }
            }
    }

    private var filteredSections: [NoteSection] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return store.sections }
        return store.sections.compactMap { section in
            let hits = section.notes.filter {
                $0.title.localizedCaseInsensitiveContains(query) || $0.bodyMd.localizedCaseInsensitiveContains(query)
            }
            return hits.isEmpty ? nil : NoteSection(title: section.title, notes: hits)
        }
    }
}

/// 一覧の1行: 題名と、チェックがあれば進み具合
private struct NoteRow: View {
    let note: Note

    var body: some View {
        let progress = NoteMarkdown.checkProgress(note.bodyMd)
        HStack {
            if note.pinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Text(note.title)
            Spacer()
            if progress.total > 0 {
                Text("\(progress.done)/\(progress.total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(progress.done == progress.total ? Color.green : Color.secondary)
            }
        }
    }
}

/// 資料1ページの中身。文章は Web ページのように選んでコピーでき、Anki カードはワンタップでコピーできる
struct NoteDetailScreen: View {
    let store: NotesStore
    let noteId: UUID

    var body: some View {
        if let note = store.note(id: noteId) {
            NoteBodyView(
                note: note,
                onToggleCheck: { line in store.toggleCheck(noteId: noteId, line: line) },
                onRefresh: { await store.sync() }
            )
            .navigationTitle(note.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 全文をまとめてコピーするボタン(Markdown のまま)
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        UIPasteboard.general.string = note.bodyMd
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .accessibilityLabel("全文をコピー")
                }
            }
        } else {
            ContentUnavailableView("この資料は消されました", systemImage: "doc.text")
        }
    }
}
