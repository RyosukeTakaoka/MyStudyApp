import SwiftUI

// ログイン後の画面。下のタブで「今日」と「週・月」を切りかえます。
struct MainTabView: View {
    let auth: AuthStore
    let userId: UUID

    var body: some View {
        TabView {
            DayScreen(auth: auth, userId: userId, local: SwiftDataStore.shared)
                .tabItem { Label("今日", systemImage: "checklist") }

            PlanBoardScreen()
                .tabItem { Label("週・月", systemImage: "rectangle.stack") }
        }
    }
}
