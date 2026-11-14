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

            // コード(``` で囲まれた部分)
            if trimmed.hasPrefix("```") {
                flushParagraph()
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i])
                    i += 1
                }
                blocks.append(.code(text: code.joined(separator: "\n")))
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

    /// line 行目のチェックを切りかえた本文を返す(チェックの行でなければそのまま)
    static func toggleCheck(in body: String, line: Int) -> String {
        var lines = body.components(separatedBy: "\n")
        guard lines.indices.contains(line) else { return body }
        let raw = lines[line]
        for (from, to) in [("[ ]", "[x]"), ("[x]", "[ ]"), ("[X]", "[ ]")] {
            if let range = raw.range(of: from), checkItem(raw.trimmingCharacters(in: .whitespaces)) != nil {
                lines[line] = raw.replacingCharacters(in: range, with: to)
                return lines.joined(separator: "\n")
            }
        }
        return body
    }

    /// チェックの数(できた数, 全部の数)
    static func checkProgress(_ body: String) -> (done: Int, total: Int) {
        var done = 0, total = 0
        for block in blocks(body) {
            if case .check(_, let checked, _, _) = block {
                total += 1
                if checked { done += 1 }
            }
        }
        return (done, total)
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
