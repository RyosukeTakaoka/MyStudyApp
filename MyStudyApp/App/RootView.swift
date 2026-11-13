import SwiftUI

// いちばん外側の画面。状態に応じて、どの画面を出すかを決めます。
struct RootView: View {
    @State private var auth = AuthStore()

    var body: some View {
        if AppConfig.isConfigured {
            content
                // 画面が出ているあいだ、ログイン状態の変化を受け取りつづける
                .task { await auth.observeAuthChanges() }
                // ログアウトしたら、端末に保存してあるデータを消す
                .onChange(of: auth.state) { _, newState in
                    if newState == .signedOut {
                        SwiftDataStore.shared.deleteEverything()
                        WidgetBridge.clear()
                        LiveActivityController.endAll()
                        StudyTimer().cancel()
                        ScreenTimeController.resetAll()
                        PlanBoardStore.clearSaved()
                        SessionQueue.clearSaved()
                        Task { await NotificationScheduler.removeAll() }
                    }
                }
        } else {
            SetupNeededView()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch auth.state {
        case .loading:
            ProgressView()
        case .signedOut:
            LoginView(auth: auth)
        case .signedIn(let userId):
            MainTabView(auth: auth, userId: userId)
                // ユーザーが変わったら、画面とデータを作り直す
                .id(userId)
        }
    }
}

#Preview {
    RootView()
}
