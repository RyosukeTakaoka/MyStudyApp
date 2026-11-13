import ActivityKit
import Foundation

// ライブアクティビティ(ロック画面とダイナミックアイランドの表示)を出したり消したりする係。
// 経過時間は表示側が自動で数えるので、始めたあとに更新する必要はありません。
@MainActor
enum LiveActivityController {
    /// 表示を始める(前の表示は消して、いつも1つだけにする)
    static func start(_ timer: RunningTimer, nextTitle: String?, nextStart: Date?) {
        // 設定アプリでライブアクティビティがオフになっていたら何もしない
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        endAll()

        let attributes = StudyActivityAttributes(itemId: timer.itemId.uuidString)
        let state = StudyActivityAttributes.ContentState(
            title: timer.title,
            subject: timer.subject,
            startedAt: timer.virtualStart,
            pausedElapsed: timer.isPaused ? timer.accumulatedSeconds : nil,
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

    /// 表示中のものを全部消す
    static func endAll() {
        for activity in Activity<StudyActivityAttributes>.activities {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// 表示中のものがあるか
    static var isShowing: Bool {
        !Activity<StudyActivityAttributes>.activities.isEmpty
    }
}
