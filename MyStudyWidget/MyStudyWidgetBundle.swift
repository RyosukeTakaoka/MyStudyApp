import SwiftUI
import WidgetKit

// ウィジェット拡張の入口。ここに並べたものが「ウィジェットを追加」の一覧に出ます。
@main
struct MyStudyWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()        // ホーム画面・ロック画面のウィジェット
        TimerWidget()        // 勉強タイマー(一時停止・完了・終了のボタンつき)
        WeekWidget()         // 今週の計画(箱の進み具合)
        StudyLiveActivity()  // ライブアクティビティ(タイマー中の表示)
    }
}
