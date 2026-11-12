import AuthenticationServices
import SwiftUI

// ログイン画面。「Apple でサインイン」ボタンだけのシンプルな画面です。
struct LoginView: View {
    let auth: AuthStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checklist")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("MyStudy")
                .font(.largeTitle.bold())
            Text("毎日の予定とタスクを確認して、\nタップでチェックするアプリです。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Spacer()

            // Apple が用意している公式のボタン
            SignInWithAppleButton(.signIn) { request in
                auth.prepareAppleRequest(request)
            } onCompletion: { result in
                Task { await auth.handleAppleCompletion(result) }
            }
            // ダークモードでは白いボタン、ライトモードでは黒いボタンにする
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 50)
            .disabled(auth.isWorking)
            // 配色が変わったらボタンを作り直す(スタイルが切りかわらないことがあるため)
            .id(colorScheme)

            if auth.isWorking {
                ProgressView("ログイン中…")
            }

            if let message = auth.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
    }
}
