import SwiftUI
import WidgetKit

// ウィジェット拡張の入口。ここに並べたものが「ウィジェットを追加」の一覧に出ます。
@main
struct MyStudyWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()        // ホーム画面・ロック画面のウィジェット
        StudyLiveActivity()  // ライブアクティビティ(タイマー中の表示)
    }
}
