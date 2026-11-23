import SwiftUI

// ログイン後の画面。下のタブで「今日」と「週・月」を切りかえます。
struct MainTabView: View {
    let auth: AuthStore
    let userId: UUID
    /// 週・月の計画。タブを開いていなくても読みこんで、「今週の計画」ウィジェットを新しく保つ
    @State private var planStore = PlanBoardStore()
    /// 答練の成績
    @State private var examStore = ExamStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            DayScreen(auth: auth, userId: userId, local: SwiftDataStore.shared)
                .tabItem { Label("今日", systemImage: "checklist") }

            PlanBoardScreen(store: planStore)
                .tabItem { Label("週・月", systemImage: "rectangle.stack") }

            ExamsScreen(store: examStore)
                .tabItem { Label("答練", systemImage: "chart.line.uptrend.xyaxis") }

            NotesScreen()
                .tabItem { Label("資料", systemImage: "doc.text") }
        }
        .task { await planStore.sync() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await planStore.sync() } }
        }
    }
}
