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
            SignedInPlaceholderView(auth: auth, userId: userId)
        }
    }
}

// ステップ3の確認用: ログインできたことと user_id を表示する。
// (ステップ4で「今日の画面」に置きかえます)
private struct SignedInPlaceholderView: View {
    let auth: AuthStore
    let userId: UUID

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("ログインできました")
                .font(.title2.bold())
            Text("あなたの user_id")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(userId.uuidString.lowercased())
                .font(.footnote.monospaced())
                .textSelection(.enabled)
            Button("ログアウト", role: .destructive) {
                Task { await auth.signOut() }
            }
            .padding(.top)
        }
        .padding()
    }
}

#Preview {
    RootView()
}
