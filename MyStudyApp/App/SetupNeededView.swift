import SwiftUI

// Secrets.xcconfig がまだ無い(または書き換え忘れている)ときに出す案内画面。
struct SetupNeededView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Supabase の設定が必要です", systemImage: "wrench.and.screwdriver")
        } description: {
            Text("""
            Config フォルダの Secrets.example.xcconfig をコピーして \
            Secrets.xcconfig を作り、SUPABASE_HOST と SUPABASE_KEY を \
            自分のプロジェクトの値に書き換えてから、もう一度実行してください。

            SUPABASE_HOST には「https://」を付けず、\
            「xxxx.supabase.co」の形で書きます。
            """)
        }
    }
}

#Preview {
    SetupNeededView()
}
