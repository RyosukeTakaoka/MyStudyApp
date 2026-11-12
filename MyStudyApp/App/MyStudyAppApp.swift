import SwiftUI

// アプリの入口。React でいう index.js / main.jsx にあたるファイルです。
// 「@main」が付いた型から、アプリが始まります。
@main
struct MyStudyAppApp: App {
    var body: some Scene {
        WindowGroup {
            // 最初に表示する画面
            RootView()
        }
    }
}
