import Foundation
import Supabase

// Supabase と通信するための「クライアント」。アプリ全体でこの1つを使い回します。
// React で `createClient(url, key)` を1回だけ呼んで export するのと同じ考え方です。
let supabase: SupabaseClient = {
    // 未設定のときはダミーの値を入れておく(RootView が先に「設定してください」画面を出すので、
    // このダミーが実際の通信に使われることはありません)
    let url = AppConfig.supabaseURL ?? URL(string: "https://not-configured.invalid")!
    let key = AppConfig.supabaseKey ?? "not-configured"

    return SupabaseClient(
        supabaseURL: url,
        supabaseKey: key,
        options: SupabaseClientOptions(
            auth: .init(
                // 端末に保存してあるログイン情報を、起動直後にそのまま使う設定。
                // これが無いと、電波がないときにログイン画面へ戻されてしまう。
                emitLocalSessionAsInitialSession: true
            )
        )
    )
}()
