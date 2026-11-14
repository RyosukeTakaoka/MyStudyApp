import SwiftUI
import UIKit

// 「資料」タブ: Claude が書いた読み物(ルール・方針・答練の振り返りなど)の一覧。
struct NotesScreen: View {
    @State private var store = NotesStore()
    @State private var searchText = ""
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
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
            .navigationTitle("資料")
            .navigationDestination(for: UUID.self) { id in
                NoteDetailScreen(store: store, noteId: id)
            }
            // 題名と本文から探せる
            .searchable(text: $searchText, prompt: "資料を検索")
            .refreshable { await store.sync() }
            .task { await store.sync() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await store.sync() } }
            }
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

/// 資料1ページの中身。文章は Web ページのように、部分選択・全選択・コピーができる
struct NoteDetailScreen: View {
    let store: NotesStore
    let noteId: UUID

    var body: some View {
        if let note = store.note(id: noteId) {
            SelectableNoteView(
                note: note,
                onToggleCheck: { line in store.toggleCheck(noteId: noteId, line: line) },
                onRefresh: { await store.sync() }
            )
            .ignoresSafeArea(edges: .bottom)
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
