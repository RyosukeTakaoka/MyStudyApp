import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import Supabase

// ログイン状態を持つ場所。
// @Observable を付けると、中の値が変わったときに画面が自動で描き直されます
// (React の useState / Context に近い仕組みです)。
@MainActor
@Observable
final class AuthStore {
    enum State: Equatable {
        case loading                 // 起動直後。保存済みのログイン情報を確認中
        case signedOut               // 未ログイン
        case signedIn(userId: UUID)  // ログイン済み
    }

    private(set) var state: State = .loading
    /// ログインに失敗したときに画面へ出す文
    var errorMessage: String?
    /// ログイン処理の最中か(ボタンの二度押しを防ぐ)
    private(set) var isWorking = false

    /// Apple に渡した「合言葉」。返ってきたトークンが本物かを Supabase が確かめるのに使う
    private var currentNonce: String?

    // MARK: - ログイン状態の見張り

    /// Supabase からの「ログインした/ログアウトした」という知らせを受け取りつづける。
    /// RootView が表示されたときに1回だけ呼ぶ。
    func observeAuthChanges() async {
        for await (event, session) in supabase.auth.authStateChanges {
            switch event {
            case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                if let session {
                    state = .signedIn(userId: session.user.id)
                } else {
                    state = .signedOut
                }
            case .signedOut, .userDeleted:
                state = .signedOut
            default:
                break
            }
        }
    }

    // MARK: - Sign in with Apple

    /// 「Apple でサインイン」ボタンが押されたとき、Apple へのお願いの中身を作る
    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        currentNonce = nonce
        request.requestedScopes = [.email]
        // Apple にはハッシュ化した値を渡し、Supabase には元の値を渡す決まり
        request.nonce = Self.sha256(nonce)
        errorMessage = nil
    }

    /// Apple の画面が閉じたあとに呼ばれる。成功していたら Supabase にログインする
    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            // 自分でキャンセルしたときは、エラーとして出さない
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                return
            }
            errorMessage = "Apple でのサインインに失敗しました。\n\(error.localizedDescription)"

        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8),
                let nonce = currentNonce
            else {
                errorMessage = "Apple から必要な情報を受け取れませんでした。もう一度お試しください。"
                return
            }

            isWorking = true
            defer { isWorking = false }
            do {
                // Apple が発行した「本人確認の証明書(ID トークン)」を Supabase に渡してログインする
                try await supabase.auth.signInWithIdToken(
                    credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
                )
                // 成功すると observeAuthChanges() に .signedIn が届き、画面が切りかわる
            } catch {
                errorMessage = """
                Supabase へのログインに失敗しました。
                Supabase の Apple 設定(Client IDs にこのアプリの Bundle ID が入っているか)を確認してください。

                \(ErrorText.message(for: error))
                """
            }
        }
    }

    // MARK: - ログアウト

    func signOut() async {
        errorMessage = nil
        do {
            // .local = この端末だけログアウトする
            try await supabase.auth.signOut(scope: .local)
        } catch {
            // ライブラリは「端末からログイン情報を消す → サーバーに知らせる」の順に動く。
            // 電波がないと後半だけ失敗するが、端末のログアウトは済んでいるので、エラーとして出さない。
            if supabase.auth.currentSession != nil {
                errorMessage = "ログアウトに失敗しました。\n\(ErrorText.message(for: error))"
            }
        }
    }

    // MARK: - nonce(合言葉)を作る道具

    /// 推測できないランダムな文字列を作る
    private static func randomNonce(length: Int = 32) -> String {
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in characters.randomElement(using: &generator)! })
    }

    /// 文字列を SHA-256 でハッシュ化して、16進数の文字にする
    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
