import SwiftUI

// いちばん外側の画面。状態に応じて、どの画面を出すかを決めます。
struct RootView: View {
    @State private var auth = AuthStore()

    var body: some View {
        if AppConfig.isConfigured {
            content
                // 画面が出ているあいだ、ログイン状態の変化を受け取りつづける
                .task { await auth.observeAuthChanges() }
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
            DayScreen(auth: auth, userId: userId)
                // ユーザーが変わったら、画面とデータを作り直す
                .id(userId)
        }
    }
}

#Preview {
    RootView()
}
