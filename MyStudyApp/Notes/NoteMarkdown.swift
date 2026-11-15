import Foundation

/// 資料ページ1つ(notes テーブルの1行)
struct Note: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var slug: String
    var title: String
    var category: String
    var bodyMd: String
    var pinned: Bool
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, slug, title, category, pinned
        case bodyMd = "body_md"
        case sortOrder = "sort_order"
    }
}

// 資料の本文(Markdown)を、画面に出す「かたまり」に分けるための計算。
// 見出し・チェック・箇条書き・番号つき・表・引用・区切り線・コード・ふつうの文 に対応します。
enum NoteMarkdown {
    enum Block: Equatable {
        case heading(level: Int, text: String)
        /// line: 本文の何行目か(0から)。チェックを押したとき、この行を書きかえる
        case check(line: Int, checked: Bool, text: String, indent: Int)
        case bullet(text: String, indent: Int)
        case numbered(number: String, text: String, indent: Int)
        case quote(text: String)
        case table(rows: [[String]])
        case code(text: String)
        case rule
        case paragraph(text: String)
        /// Anki カード(表・裏と、コピーのボタンつきで表示する)
        case card(AnkiCard)
    }

    /// Anki カード1枚。本文ではこう書く:
    ///
    ///     ```anki [ ] ① 問1
    ///     表の文
    ///     ---
    ///     裏の文(何行でもよい)
    ///     ```
    ///
    /// [ ] は「追加済み」のチェック([x] で追加済み)。そのあとが見出し
    struct AnkiCard: Equatable {
        /// 本文の何行目か(``` の行)。「追加済み」を押したとき、この行を書きかえる
        let line: Int
        let added: Bool
        let label: String
        let front: String
        let back: String
    }

    /// 画面に出すまとまり: ふつうの文章のかたまり / カード1枚
    enum Chunk: Equatable {
        case text([Block])
        case card(AnkiCard)
    }

    /// 本文をかたまりに分ける
    static func blocks(_ body: String) -> [Block] {
        let lines = body.components(separatedBy: "\n")
        var blocks: [Block] = []
        var paragraph: [String] = []
        var i = 0

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(text: paragraph.joined(separator: "\n")))
                paragraph = []
            }
        }

        while i < lines.count {
            let raw = lines[i]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            let indent = (raw.prefix { $0 == " " }.count) / 2

            // コード(``` で囲まれた部分)。```anki なら Anki カード
            if trimmed.hasPrefix("```") {
                flushParagraph()
                let fenceLine = i
                let info = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i])
                    i += 1
                }
                if info.lowercased().hasPrefix("anki") {
                    blocks.append(.card(ankiCard(info: String(info.dropFirst(4)), body: code, line: fenceLine)))
                } else {
                    blocks.append(.code(text: code.joined(separator: "\n")))
                }
                i += 1
                continue
            }
            // 表(| で始まる行が続く部分)
            if trimmed.hasPrefix("|") {
                flushParagraph()
                var rows: [[String]] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    let row = lines[i].trimmingCharacters(in: .whitespaces)
                    if !isTableSeparator(row) { rows.append(tableCells(row)) }
                    i += 1
                }
                blocks.append(.table(rows: rows))
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
            } else if let heading = headingLevel(trimmed) {
                flushParagraph()
                blocks.append(.heading(level: heading.level, text: heading.text))
            } else if let check = checkItem(trimmed) {
                flushParagraph()
                blocks.append(.check(line: i, checked: check.checked, text: check.text, indent: indent))
            } else if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(.rule)
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                flushParagraph()
                blocks.append(.bullet(text: String(trimmed.dropFirst(2)), indent: indent))
            } else if let numbered = numberedItem(trimmed) {
                flushParagraph()
                blocks.append(.numbered(number: numbered.number, text: numbered.text, indent: indent))
            } else if trimmed.hasPrefix(">") {
                flushParagraph()
                blocks.append(.quote(text: trimmed.dropFirst().trimmingCharacters(in: .whitespaces)))
            } else {
                paragraph.append(trimmed)
            }
            i += 1
        }
        flushParagraph()
        return blocks
    }

    /// かたまりを、画面に出すまとまりに分ける(カードの前後で文章を区切る)
    static func chunks(_ blocks: [Block]) -> [Chunk] {
        var result: [Chunk] = []
        var text: [Block] = []
        for block in blocks {
            if case .card(let card) = block {
                if !text.isEmpty { result.append(.text(text)); text = [] }
                result.append(.card(card))
            } else {
                text.append(block)
            }
        }
        if !text.isEmpty { result.append(.text(text)) }
        return result
    }

    /// line 行目のチェックを切りかえた本文を返す(チェックやカードの行でなければそのまま)
    static func toggleCheck(in body: String, line: Int) -> String {
        var lines = body.components(separatedBy: "\n")
        guard lines.indices.contains(line) else { return body }
        let raw = lines[line]
        // Anki カードの「追加済み」
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().hasPrefix("```anki") {
            if let range = raw.range(of: "[ ]") {
                lines[line] = raw.replacingCharacters(in: range, with: "[x]")
            } else if let range = raw.range(of: "[x]") ?? raw.range(of: "[X]") {
                lines[line] = raw.replacingCharacters(in: range, with: "[ ]")
            } else if let range = raw.range(of: "```anki", options: .caseInsensitive) {
                lines[line] = raw.replacingCharacters(in: range, with: "```anki [x]")
            }
            return lines.joined(separator: "\n")
        }
        for (from, to) in [("[ ]", "[x]"), ("[x]", "[ ]"), ("[X]", "[ ]")] {
            if let range = raw.range(of: from), checkItem(raw.trimmingCharacters(in: .whitespaces)) != nil {
                lines[line] = raw.replacingCharacters(in: range, with: to)
                return lines.joined(separator: "\n")
            }
        }
        return body
    }

    /// チェックの数(できた数, 全部の数)。Anki カードの「追加済み」もふくむ
    static func checkProgress(_ body: String) -> (done: Int, total: Int) {
        var done = 0, total = 0
        for block in blocks(body) {
            switch block {
            case .check(_, let checked, _, _):
                total += 1
                if checked { done += 1 }
            case .card(let card):
                total += 1
                if card.added { done += 1 }
            default:
                break
            }
        }
        return (done, total)
    }

    /// ```anki の行のあと(例 " [x] ① 問1")と中身から、カードを作る
    private static func ankiCard(info: String, body: [String], line: Int) -> AnkiCard {
        var rest = info.trimmingCharacters(in: .whitespaces)
        var added = false
        if rest.hasPrefix("[x]") || rest.hasPrefix("[X]") {
            added = true
            rest = String(rest.dropFirst(3))
        } else if rest.hasPrefix("[ ]") {
            rest = String(rest.dropFirst(3))
        }
        // 「---」だけの行で、表と裏を分ける
        let parts = body.split(omittingEmptySubsequences: false) { $0.trimmingCharacters(in: .whitespaces) == "---" }
        let front = (parts.first ?? []).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let back = parts.dropFirst().map { $0.joined(separator: "\n") }.joined(separator: "\n---\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return AnkiCard(line: line, added: added, label: rest.trimmingCharacters(in: .whitespaces), front: front, back: back)
    }

    // MARK: - 中で使う道具

    private static func headingLevel(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return (hashes, String(line.dropFirst(hashes + 1)))
    }

    private static func checkItem(_ line: String) -> (checked: Bool, text: String)? {
        for prefix in ["- ", "* ", "+ "] where line.hasPrefix(prefix) {
            let rest = line.dropFirst(2)
            if rest.hasPrefix("[ ] ") || rest == "[ ]" { return (false, String(rest.dropFirst(4))) }
            if rest.hasPrefix("[x] ") || rest.hasPrefix("[X] ") || rest == "[x]" || rest == "[X]" {
                return (true, String(rest.dropFirst(4)))
            }
        }
        return nil
    }

    private static func numberedItem(_ line: String) -> (number: String, text: String)? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") else { return nil }
        return (String(digits), String(line.dropFirst(digits.count + 2)))
    }

    private static func isTableSeparator(_ row: String) -> Bool {
        row.allSatisfy { "|-: ".contains($0) } && row.contains("-")
    }

    private static func tableCells(_ row: String) -> [String] {
        var cells = row.split(separator: "|", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        if cells.first == "" { cells.removeFirst() }
        if cells.last == "" { cells.removeLast() }
        return cells
    }
}
