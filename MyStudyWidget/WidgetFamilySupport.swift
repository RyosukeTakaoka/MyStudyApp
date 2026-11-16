import SwiftUI
import WidgetKit

// iOS 27 で増えた、iPhone の特大ウィジェット(たて長・ホーム画面1ページ分)の扱い。
// 古い Xcode(27 より前)はこの大きさの名前を知らないので、#if compiler でとばします。
extension WidgetFamily {
    /// 特大(たて長)か。iOS 27 より前では、いつも false
    var isExtraLargePortrait: Bool {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            return self == .systemExtraLargePortrait
        }
        #endif
        return false
    }

    /// 大きさの一覧に、使えるなら特大(たて長)を足す
    static func withExtraLargePortrait(_ list: [WidgetFamily]) -> [WidgetFamily] {
        var list = list
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            list.append(.systemExtraLargePortrait)
        }
        #endif
        return list
    }
}

/// 経過時間の文字(例 1:05:09 / 12:30)
enum ElapsedFormat {
    static func text(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// 枠に入るだけ行を並べる部品(メールのウィジェットのように、上も下も途中で切れない)。
/// 行の数を多い順にためして、見出しから最後の行まで枠に収まるいちばん多い数を選ぶ。
/// 入らなかった分は「ほか N 件」と出す。
///
/// ViewThatFits: 中に並べた見た目の候補を上から順にためし、枠に入った最初のものを使う SwiftUI の部品
struct FitRows<Item, Header: View, Row: View>: View {
    let items: [Item]
    /// 多くてもこの数まで(ためす数を減らして、ウィジェットを速く描くため)
    var maxCount: Int = 30
    var spacing: CGFloat = 8
    /// 行と行のあいだに区切り線を入れるか(メモのウィジェットのように)
    var dividers: Bool = false
    /// n 行にするとき、どの行を出すか(ふつうは先頭から n 個)
    var pick: ([Item], Int) -> [Item] = { items, n in Array(items.prefix(n)) }
    /// 一覧の上に出すもの(日付・進み具合など)
    @ViewBuilder var header: () -> Header
    /// 1行の見た目(shown = 出す行の一覧、index = その中の何番目か)
    @ViewBuilder var row: (_ shown: [Item], _ index: Int) -> Row

    var body: some View {
        ViewThatFits(in: .vertical) {
            ForEach(counts, id: \.self) { n in
                column(pick(items, n))
            }
        }
        // 上から詰める(はみ出しても、上の見出しは切れない)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// ためす行の数(多い順。最後は0行 = 見出しだけ)
    private var counts: [Int] {
        Array((0...min(maxCount, items.count)).reversed())
    }

    private func column(_ shown: [Item]) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            header()
            ForEach(shown.indices, id: \.self) { index in
                if dividers && index > 0 {
                    Divider()
                }
                row(shown, index)
            }
            if items.count > shown.count {
                // 入らなかった分(最後の行は必ず全部見えるようにしてある)
                Label("ほか \(items.count - shown.count) 件", systemImage: "ellipsis.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// ウィジェットの外わく。中サイズ以上では、いちばん上に色つきの帯(アイコン・アプリ名・ウィジェットの名前)を出す。
/// メモのウィジェットのように、帯の下に中身を上から詰めて並べる。
/// (帯を端までぬるために、設定で余白〔contentMargins〕を切り、中身の余白はここで付け直す)
struct WidgetFrame<Content: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    /// 帯の右に出す短い文字(例 "8/11")
    var trailing: String? = nil
    @ViewBuilder var content: () -> Content

    @Environment(\.widgetFamily) private var family
    /// その大きさでの、ふつうの余白(OS が決める)
    @Environment(\.widgetContentMargins) private var margins

    var body: some View {
        if showsBand {
            VStack(alignment: .leading, spacing: 0) {
                band
                content()
                    .padding(.top, 10)
                    .padding(.leading, margins.leading)
                    .padding(.trailing, margins.trailing)
                    .padding(.bottom, max(10, margins.bottom * 0.75))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else {
            content()
                .padding(margins)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// 帯を出す大きさ(小とロック画面はせまいので出さない)
    private var showsBand: Bool {
        switch family {
        case .systemMedium, .systemLarge, .systemExtraLarge: return true
        default: return family.isExtraLargePortrait
        }
    }

    private var band: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.subheadline.bold())
            Text("MyStudy")
                .font(.subheadline.bold())
            Text(title)
                .font(.subheadline)
                .opacity(0.9)
            Spacer(minLength: 4)
            if let trailing {
                Text(trailing)
                    .font(.subheadline.monospacedDigit().bold())
            }
        }
        .lineLimit(1)
        .foregroundStyle(.white)
        .padding(.horizontal, margins.leading)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.gradient)
        .widgetAccentable()
    }
}
