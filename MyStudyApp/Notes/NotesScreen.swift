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

/// 資料1ページの中身
struct NoteDetailScreen: View {
    let store: NotesStore
    let noteId: UUID

    var body: some View {
        if let note = store.note(id: noteId) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(note.category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(Array(NoteMarkdown.blocks(note.bodyMd).enumerated()), id: \.offset) { _, block in
                        MarkdownBlockView(block: block) { line in
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            store.toggleCheck(noteId: noteId, line: line)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(note.title)
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await store.sync() }
        } else {
            ContentUnavailableView("この資料は消されました", systemImage: "doc.text")
        }
    }
}

/// かたまり1つの表示
private struct MarkdownBlockView: View {
    let block: NoteMarkdown.Block
    let onToggle: (Int) -> Void

    var body: some View {
        switch block {
        case .heading(let level, let text):
            inline(text)
                .font(level == 1 ? .title2.bold() : level == 2 ? .title3.bold() : .headline)
                .padding(.top, level <= 2 ? 10 : 4)
        case .check(let line, let checked, let text, let indent):
            Button {
                onToggle(line)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: checked ? "checkmark.square.fill" : "square")
                        .foregroundStyle(checked ? Color.green : Color.secondary)
                    inline(text)
                        .strikethrough(checked)
                        .foregroundStyle(checked ? Color.secondary : Color.primary)
                        .multilineTextAlignment(.leading)
                }
                .padding(.leading, CGFloat(indent) * 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        case .bullet(let text, let indent):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(indent == 0 ? "•" : "◦")
                inline(text)
            }
            .padding(.leading, CGFloat(indent) * 16)
        case .numbered(let number, let text, let indent):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(number).")
                    .monospacedDigit()
                inline(text)
            }
            .padding(.leading, CGFloat(indent) * 16)
        case .quote(let text):
            inline(text)
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color.secondary.opacity(0.4)).frame(width: 3)
                }
        case .table(let rows):
            TableView(rows: rows)
        case .code(let text):
            Text(text)
                .font(.footnote.monospaced())
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        case .rule:
            Divider()
        case .paragraph(let text):
            inline(text)
        }
    }

    /// **太字** や `コード`、リンクなどを反映した文字
    private func inline(_ text: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(text)
    }
}

/// 表(1行目を見出しとして太字にする)。横に長いときは横にスクロールできる
private struct TableView: View {
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            cellText(cell)
                                .font(index == 0 ? .subheadline.bold() : .subheadline)
                                .frame(maxWidth: 260, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if index == 0 {
                        Divider()
                    }
                }
            }
            .padding(10)
        }
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private func cellText(_ cell: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: cell, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(cell)
    }
}
