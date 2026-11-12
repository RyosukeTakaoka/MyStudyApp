import Foundation

// サーバーから届いたデータと、端末内のデータを「どう合体させるか」を決めるロジック。
//
// 基本ルール:
//   ・サーバーの内容が正しいものとして、端末内を上書きする
//   ・ただし「まだサーバーに送っていない変更」(チェックやふりかえり)は、端末側を優先して残す
//   ・サーバーから消えた行は、端末内からも消す(Claude が予定を入れ直したとき)
enum SyncMerge {
    struct ItemChanges: Equatable {
        var save: [LocalItem] = []
        var deleteIds: [UUID] = []
    }

    struct DayChanges: Equatable {
        var save: [LocalDay] = []
        var deleteDates: [String] = []
    }

    /// - Parameters:
    ///   - server: サーバーから読んだ、ある期間の予定
    ///   - local: 端末内にある、同じ期間の予定
    static func items(server: [PlanItem], local: [LocalItem]) -> ItemChanges {
        var changes = ItemChanges()
        let localById = Dictionary(local.map { ($0.item.id, $0) }, uniquingKeysWith: { first, _ in first })

        for serverItem in server {
            if let mine = localById[serverItem.id], mine.needsSync {
                // 未送信のチェックがある行: タイトルや時刻はサーバーに合わせ、チェックだけ端末側を残す
                var merged = serverItem
                merged.done = mine.item.done
                merged.doneAt = mine.item.doneAt
                changes.save.append(LocalItem(item: merged, needsSync: true))
            } else {
                changes.save.append(LocalItem(item: serverItem, needsSync: false))
            }
        }

        // サーバーに無い行は端末からも消す。
        // 未送信の変更がある行だけは、送信がすむまで残しておく(次の同期で送ったあとに消える)
        let serverIds = Set(server.map(\.id))
        changes.deleteIds = local
            .filter { !serverIds.contains($0.item.id) && !$0.needsSync }
            .map(\.item.id)
        return changes
    }

    /// - Parameters:
    ///   - server: サーバーから読んだ、ある期間の「1日の情報」
    ///   - local: 端末内にある、同じ期間の「1日の情報」
    ///   - dates: その期間の日付を全部ならべたもの
    static func days(server: [DayInfo], local: [LocalDay], dates: [String]) -> DayChanges {
        var changes = DayChanges()
        let serverByDate = Dictionary(server.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        let localByDate = Dictionary(local.map { ($0.info.date, $0) }, uniquingKeysWith: { first, _ in first })

        for date in dates {
            let mine = localByDate[date]
            if let serverDay = serverByDate[date] {
                if let mine, mine.reflectionNeedsSync {
                    // 未送信のふりかえりがある日: 目標はサーバーに合わせ、ふりかえりは端末側を残す
                    let merged = DayInfo(date: date, goal: serverDay.goal, reflection: mine.info.reflection)
                    changes.save.append(LocalDay(info: merged, reflectionNeedsSync: true))
                } else {
                    changes.save.append(LocalDay(info: serverDay, reflectionNeedsSync: false))
                }
            } else if let mine, !mine.reflectionNeedsSync {
                // サーバーに行が無く、端末にも未送信の変更が無い → 端末からも消す
                changes.deleteDates.append(date)
            }
        }
        return changes
    }
}
