import SwiftUI
import UIKit

// 資料の本文の表示。
//   ・ふつうの文章 … Web ページのように、部分選択・全選択・コピーができる(SelectableTextBlock)
//   ・Anki カード   … 表と裏に「コピー」ボタンがあり、ワンタップでコピーできる(AnkiCardView)
struct NoteBodyView: View {
    let note: Note
    /// □ や「追加済み」が押されたとき(本文の何行目か)
    let onToggleCheck: (Int) -> Void
    /// 下に引っぱって更新したとき
    let onRefresh: () async -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(note.category)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Array(NoteMarkdown.chunks(NoteMarkdown.blocks(note.bodyMd)).enumerated()), id: \.offset) { _, chunk in
                    switch chunk {
                    case .text(let blocks):
                        SelectableTextBlock(text: NoteAttributedText.make(blocks: blocks), onToggleCheck: onToggleCheck)
                    case .card(let card):
                        AnkiCardView(card: card) { onToggleCheck(card.line) }
                    }
                }
            }
            .padding()
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await onRefresh() }
    }
}

/// Anki カード1枚: 見出し・追加済みのチェック・表と裏(それぞれコピーのボタンつき)
struct AnkiCardView: View {
    let card: NoteMarkdown.AnkiCard
    let onToggleAdded: () -> Void

    /// 今「コピーしました」と出している側("表" / "裏")
    @State private var copied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(card.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    onToggleAdded()
                } label: {
                    Label("追加済み", systemImage: card.added ? "checkmark.square.fill" : "square")
                        .font(.subheadline)
                        .foregroundStyle(card.added ? Color.green : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityValue(card.added ? "追加済み" : "まだ")
            }

            side("表", text: card.front)
            if !card.back.isEmpty {
                // 点線の区切り
                Line()
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color.secondary.opacity(0.4))
                    .frame(height: 1)
                side("裏", text: card.back)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(card.added ? Color.green.opacity(0.5) : Color.secondary.opacity(0.25))
        }
        // 追加済みのカードは、少しうすくする
        .opacity(card.added ? 0.6 : 1)
    }

    /// 「表」「裏」の1段: 文章(選んでコピーもできる)と、ワンタップのコピーボタン
    private func side(_ name: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(name)
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Button {
                UIPasteboard.general.string = text
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                copied = name
                // 1.5秒たったら、ボタンの文字を元に戻す
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.5))
                    if copied == name { copied = nil }
                }
            } label: {
                Text(copied == name ? "コピーしました" : "\(name)をコピー")
                    .font(.subheadline.bold())
                    .frame(minWidth: 96)
            }
            .buttonStyle(.borderedProminent)
            .tint(copied == name ? .green : .accentColor)
        }
    }

    /// 横線の形
    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            }
        }
    }
}

/// ふつうの文章のかたまり。Web ページのように選べる・コピーできる(高さは中身に合わせて自動)
struct SelectableTextBlock: UIViewRepresentable {
    let text: NSAttributedString
    let onToggleCheck: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false          // 書きかえはできない
        textView.isSelectable = true         // 選べる・コピーできる
        textView.isScrollEnabled = false     // スクロールは外側にまかせ、高さを中身に合わせる
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = true
        // リンクの色は本文の中で決める(□ を青い下線つきにしないため)
        textView.linkTextAttributes = [:]
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.delegate = context.coordinator
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        // 中身が変わったときだけ描き直す(選んでいる範囲が勝手に消えないように)
        if !textView.attributedText.isEqual(to: text) {
            textView.attributedText = text
        }
    }

    /// 横幅に合わせて、必要な高さを計算する
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(size.height))
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SelectableTextBlock

        init(parent: SelectableTextBlock) {
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

    static func make(blocks: [NoteMarkdown.Block]) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for block in blocks {
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

            case .card:
                break   // カードは AnkiCardView で別に表示する
            }
        }
        // 最後の改行は取る(かたまりの下に、よけいなすき間ができないように)
        if out.string.hasSuffix("\n") {
            out.deleteCharacters(in: NSRange(location: out.length - 1, length: 1))
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
