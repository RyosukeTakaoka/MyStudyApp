import ActivityKit
import Foundation

// ライブアクティビティ(ロック画面とダイナミックアイランドの表示)を出したり消したりする係。
// 経過時間は表示側が自動で数えるので、始めたあとに更新する必要はありません。
@MainActor
enum LiveActivityController {
    /// 表示を始める(タイマーごとに1つ。同じ予定の表示があれば、出し直す)
    static func start(_ timer: RunningTimer, nextTitle: String?, nextStart: Date?) {
        // 設定アプリでライブアクティビティがオフになっていたら何もしない
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        end(itemId: timer.itemId)

        let attributes = StudyActivityAttributes(itemId: timer.itemId.uuidString)
        let state = StudyActivityAttributes.ContentState(
            title: timer.title,
            subject: timer.subject,
            startedAt: timer.displayStart,
            pausedElapsed: timer.isPaused ? timer.priorSeconds + timer.accumulatedSeconds : nil,
            plannedEnd: timer.plannedEnd,
            nextTitle: nextTitle,
            nextStart: nextStart
        )
        do {
            _ = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil   // サーバーからの更新は使わない
            )
        } catch {
            print("ライブアクティビティを開始できませんでした: \(error)")
        }
    }

    /// その予定の表示を消す
    static func end(itemId: UUID) {
        for activity in Activity<StudyActivityAttributes>.activities where activity.attributes.itemId == itemId.uuidString {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// その予定の表示があるか
    static func isShowing(itemId: UUID) -> Bool {
        Activity<StudyActivityAttributes>.activities.contains { $0.attributes.itemId == itemId.uuidString }
    }

    /// 表示中のものを全部消す
    static func endAll() {
        for activity in Activity<StudyActivityAttributes>.activities {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

}
