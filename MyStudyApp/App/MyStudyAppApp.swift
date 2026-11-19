import SwiftUI

// アプリの入口。React でいう index.js / main.jsx にあたるファイルです。
// 「@main」が付いた型から、アプリが始まります。
@main
struct MyStudyAppApp: App {
    init() {
        // 自動タイマーはオフ・予定の時間は自動で集中モード、に1回だけ切りかえる(ユーザーの希望)
        AppSettings.applyFocusAutoDefaultsOnce()

        // ウィジェットのボタンでタイマーが変わったとき(アプリの中で動く)に、
        // ロック画面のライブアクティビティを直し、画面に「読み直して」と知らせる
        TimerWidgetActions.onChange = { event in
            switch event.action {
            case .stop:
                LiveActivityController.end(itemId: event.itemId)
            case .pause, .resume:
                if let timer = StudyTimer().timer(for: event.itemId) {
                    LiveActivityController.update(timer)
                }
            }
            // 勉強のタイマーがもう動いていなければ、タイマーでかけた集中モードを外す
            // (アプリの画面が開いていないときでも外れるように、ここでも行う)
            let studying = StudyTimer().activeTimers.contains { StudyKind.isStudy(subject: $0.subject, title: $0.title) }
            if !studying {
                ScreenTimeController().endForTimer()
            }
            NotificationCenter.default.post(name: .studyTimerChangedFromWidget, object: nil)
        }
    }

    var body: some Scene {
        WindowGroup {
            // 最初に表示する画面
            RootView()
        }
    }
}
