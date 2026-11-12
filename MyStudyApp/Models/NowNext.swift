import Foundation

// 「今やる予定」と「その次の予定」を決めるロジック。
//
// 画面(SwiftUI)にもデータベースにも頼らない、ただの計算にしてあります。
// こうしておくと、次の版でホーム画面ウィジェットを作るときにも、このファイルをそのまま使えます。
struct NowNext: Equatable {
    /// 今の時刻に当たっている予定(無ければ nil)
    var current: PlanItem?
    /// その次に始まる予定(無ければ nil)
    var next: PlanItem?
    /// 今の予定が終わるまでの分数
    var minutesLeft: Int?
    /// 次の予定が始まるまでの分数
    var minutesUntilNext: Int?

    /// - Parameters:
    ///   - items: その日の予定とタスク(順番はバラバラでもよい)
    ///   - nowMinutes: 今の時刻を「0時からの分数」で表したもの(16:30 → 990)
    static func compute(items: [PlanItem], nowMinutes: Int) -> NowNext {
        // 時間つきの予定だけを、開始時刻の早い順にならべる
        let blocks = PlanItem.sortedForDisplay(items.filter { $0.isBlock && $0.startMinutes != nil })

        // 今 = 「開始 <= 今 < 終了」の予定。重なっているときは、あとから始まったほうを選ぶ
        let current = blocks.last { block in
            guard let start = block.startMinutes, let end = block.endMinutes else { return false }
            return start <= nowMinutes && nowMinutes < end
        }
        // 次 = 今より後に始まる予定のうち、いちばん早いもの
        let next = blocks.first { ($0.startMinutes ?? 0) > nowMinutes }

        return NowNext(
            current: current,
            next: next,
            minutesLeft: current?.endMinutes.map { $0 - nowMinutes },
            minutesUntilNext: next?.startMinutes.map { $0 - nowMinutes }
        )
    }

    /// 分数を「あと1時間20分」のような文字にする
    static func durationText(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest)分" }
        if rest == 0 { return "\(hours)時間" }
        return "\(hours)時間\(rest)分"
    }
}
