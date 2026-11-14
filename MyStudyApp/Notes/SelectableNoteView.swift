import SwiftUI
import UIKit

// 資料の本文を、Web ページのように自由に選べる形で表示する部品。
// iPhone のメモや Safari と同じ文章の部品(UITextView)を使うので、
// 長押しで部分選択・範囲の調整・全選択・コピー・調べる などがそのまま使えます。
// □(チェック)は押すとチェックが切りかわります。
struct SelectableNoteView: UIViewRepresentable {
    let note: Note
    /// □ が押されたとき(本文の何行目か)
    let onToggleCheck: (Int) -> Void
    /// 下に引っぱって更新したとき
    let onRefresh: () async -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false          // 書きかえはできない
        textView.isSelectable = true         // 選べる・コピーできる
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.backgroundColor = .systemBackground
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 40, right: 16)
        textView.adjustsFontForContentSizeCategory = true
        // リンクの色は本文の中で決める(□ を青い下線つきにしないため)
        textView.linkTextAttributes = [:]
        textView.delegate = context.coordinator

        let refresh = UIRefreshControl()
        refresh.addTarget(context.coordinator, action: #selector(Coordinator.refresh(_:)), for: .valueChanged)
        textView.refreshControl = refresh
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        // 中身が変わったときだけ描き直す(選んでいる範囲が勝手に消えないように)
        let key = note.category + "\u{0}" + note.bodyMd
        guard key != context.coordinator.renderedKey else { return }
        context.coordinator.renderedKey = key
        let offset = textView.contentOffset
        textView.attributedText = NoteAttributedText.make(note: note)
        textView.layoutIfNeeded()
        // □ を押して描き直したときに、読んでいた場所がずれないようにする
        textView.setContentOffset(offset, animated: false)
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SelectableNoteView
        var renderedKey: String?

        init(parent: SelectableNoteView) {
            self.parent = parent
        }

        /// リンクが押されたとき: □ ならチェックを切りかえ、ふつうのリンクならそのまま開く
        func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
            if case .link(let url) = textItem.content, let line = NoteAttributedText.checkLine(from: url) {
                return UIAction { [weak self] _ in
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    self?.parent.onToggleCheck(line)
                }
            }
            return defaultAction
        }

        /// □ を長押ししたときに、リンクのメニューを出さない
        func textView(_ textView: UITextView, menuConfigurationFor textItem: UITextItem, defaultMenu: UIMenu) -> UITextItem.MenuConfiguration? {
            if case .link(let url) = textItem.content, NoteAttributedText.checkLine(from: url) != nil {
                return nil
            }
            return UITextItem.MenuConfiguration(menu: defaultMenu)
        }

        @objc func refresh(_ control: UIRefreshControl) {
            Task { @MainActor in
                await parent.onRefresh()
                control.endRefreshing()
            }
        }
    }
}

/// 資料の本文(Markdown)を、文字の飾りつき(NSAttributedString)に変える
enum NoteAttributedText {
    private static let checkScheme = "mystudy-check"

    /// □ に付けるリンク(本文の何行目かを入れておく)
    static func checkURL(line: Int) -> URL {
        URL(string: "\(checkScheme)://line/\(line)")!
    }

    static func checkLine(from url: URL) -> Int? {
        guard url.scheme == checkScheme else { return nil }
        return Int(url.lastPathComponent)
    }

    static func make(note: Note) -> NSAttributedString {
        let out = NSMutableAttributedString()
        appendLine(out, NSAttributedString(string: note.category, attributes: [
            .font: UIFont.preferredFont(forTextStyle: .caption1),
            .foregroundColor: UIColor.secondaryLabel,
        ]), style: paragraph(after: 8))

        for block in NoteMarkdown.blocks(note.bodyMd) {
            switch block {
            case .heading(let level, let text):
                let style: UIFont.TextStyle = level == 1 ? .title2 : level == 2 ? .title3 : .headline
                let font = bold(UIFont.preferredFont(forTextStyle: style))
                appendLine(out, inline(text, font: font), style: paragraph(before: level <= 2 ? 14 : 8, after: 4))

            case .paragraph(let text):
                appendLine(out, inline(text, font: body), style: paragraph(after: 8))

            case .check(let line, let checked, let text, let indent):
                let left = CGFloat(indent) * 20
                let row = NSMutableAttributedString(string: checked ? "☑\u{FE0E}" : "☐", attributes: [
                    .font: UIFont.systemFont(ofSize: body.pointSize * 1.25),
                    .foregroundColor: checked ? UIColor.systemGreen : UIColor.secondaryLabel,
                    .link: checkURL(line: line),
                ])
                row.append(NSAttributedString(string: "\t", attributes: [.font: body]))
                let content = NSMutableAttributedString(attributedString: inline(text, font: body))
                if checked {
                    let range = NSRange(location: 0, length: content.length)
                    content.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                    content.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: range)
                }
                row.append(content)
                appendLine(out, row, style: hanging(left: left, marker: 28, after: 6))

            case .bullet(let text, let indent):
                let left = CGFloat(indent) * 20
                let row = NSMutableAttributedString(string: indent == 0 ? "•\t" : "◦\t", attributes: [.font: body, .foregroundColor: UIColor.label])
                row.append(inline(text, font: body))
                appendLine(out, row, style: hanging(left: left, marker: 18, after: 4))

            case .numbered(let number, let text, let indent):
                let left = CGFloat(indent) * 20
                let row = NSMutableAttributedString(string: "\(number).\t", attributes: [
                    .font: UIFont.monospacedDigitSystemFont(ofSize: body.pointSize, weight: .regular),
                    .foregroundColor: UIColor.label,
                ])
                row.append(inline(text, font: body))
                appendLine(out, row, style: hanging(left: left, marker: 28, after: 4))

            case .quote(let text):
                let quote = NSMutableAttributedString(attributedString: inline(text, font: body))
                quote.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: NSRange(location: 0, length: quote.length))
                let row = NSMutableAttributedString(string: "┃ ", attributes: [.font: body, .foregroundColor: UIColor.tertiaryLabel])
                row.append(quote)
                appendLine(out, row, style: hanging(left: 0, marker: 16, after: 8))

            case .table(let rows):
                appendTable(out, rows: rows)

            case .code(let text):
                let code = NSAttributedString(string: text, attributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize, weight: .regular),
                    .foregroundColor: UIColor.label,
                    .backgroundColor: UIColor.secondarySystemFill,
                ])
                appendLine(out, code, style: paragraph(before: 4, after: 8))

            case .rule:
                appendLine(out, NSAttributedString(string: String(repeating: "─", count: 24), attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .footnote),
                    .foregroundColor: UIColor.separator,
                ]), style: paragraph(before: 6, after: 6))
            }
        }
        return out
    }

    // MARK: - 中で使う道具

    private static var body: UIFont { UIFont.preferredFont(forTextStyle: .body) }

    /// 1行(段落)を足す
    private static func appendLine(_ out: NSMutableAttributedString, _ line: NSAttributedString, style: NSParagraphStyle) {
        let row = NSMutableAttributedString(attributedString: line)
        row.append(NSAttributedString(string: "\n"))
        row.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: row.length))
        out.append(row)
    }

    private static func paragraph(before: CGFloat = 0, after: CGFloat = 0) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = before
        style.paragraphSpacing = after
        style.lineSpacing = 2
        return style
    }

    /// 先頭の印(•・番号・□)のあと、折り返した行が文字の頭にそろう段落
    private static func hanging(left: CGFloat, marker: CGFloat, after: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = left
        style.headIndent = left + marker
        style.tabStops = [NSTextTab(textAlignment: .left, location: left + marker)]
        style.defaultTabInterval = marker
        style.paragraphSpacing = after
        style.lineSpacing = 2
        return style
    }

    /// 表: セルのあいだをタブで区切る(コピーして表計算アプリに貼ると、表になる)
    private static func appendTable(_ out: NSMutableAttributedString, rows: [[String]]) {
        guard !rows.isEmpty else { return }
        let font = UIFont.preferredFont(forTextStyle: .subheadline)
        let columns = rows.map(\.count).max() ?? 0
        // 列の幅: その列のいちばん長い文字数から決める(長すぎる列は打ち切る)
        var stops: [NSTextTab] = []
        var x: CGFloat = 0
        for column in 0..<max(0, columns - 1) {
            let longest = rows.map { $0.indices.contains(column) ? $0[column].count : 0 }.max() ?? 0
            x += min(CGFloat(longest), 12) * font.pointSize + 16
            stops.append(NSTextTab(textAlignment: .left, location: x))
        }
        for (index, row) in rows.enumerated() {
            let line = NSMutableAttributedString()
            for (column, cell) in row.enumerated() {
                if column > 0 { line.append(NSAttributedString(string: "\t", attributes: [.font: font])) }
                line.append(inline(cell, font: index == 0 ? bold(font) : font))
            }
            let style = NSMutableParagraphStyle()
            style.tabStops = stops
            style.headIndent = 0
            style.paragraphSpacing = index == 0 ? 6 : 4
            style.paragraphSpacingBefore = index == 0 ? 4 : 0
            if index == 0 {
                line.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: line.length))
            }
            appendLine(out, line, style: style)
        }
        // 表のあとに少し間をあける
        appendLine(out, NSAttributedString(string: ""), style: paragraph(after: 4))
    }

    /// **太字**・*斜体*・`コード`・~~打ち消し~~・[リンク](URL) を反映した文字
    private static func inline(_ text: String, font: UIFont) -> NSAttributedString {
        let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.label]
        guard let parsed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return NSAttributedString(string: text, attributes: base)
        }
        let out = NSMutableAttributedString()
        for run in parsed.runs {
            let piece = String(parsed[run.range].characters)
            var attributes = base
            var runFont = font
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.code) {
                    runFont = UIFont.monospacedSystemFont(ofSize: font.pointSize * 0.95, weight: .regular)
                    attributes[.backgroundColor] = UIColor.secondarySystemFill
                }
                if intent.contains(.stronglyEmphasized) { runFont = bold(runFont) }
                if intent.contains(.emphasized) { runFont = italic(runFont) }
                if intent.contains(.strikethrough) {
                    attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                }
            }
            if let link = run.link {
                attributes[.link] = link
                attributes[.foregroundColor] = UIColor.systemBlue
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            attributes[.font] = runFont
            out.append(NSAttributedString(string: piece, attributes: attributes))
        }
        return out
    }

    private static func bold(_ font: UIFont) -> UIFont {
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.traitBold)) else { return font }
        return UIFont(descriptor: descriptor, size: 0)
    }

    private static func italic(_ font: UIFont) -> UIFont {
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.traitItalic)) else { return font }
        return UIFont(descriptor: descriptor, size: 0)
    }
}
