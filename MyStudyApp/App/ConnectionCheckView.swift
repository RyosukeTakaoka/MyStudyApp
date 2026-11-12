import SwiftUI
import Supabase

// ステップ2の確認用画面: Supabase に実際に問い合わせて、つながるかを確かめます。
// (ステップ3でログイン画面に置きかえます)
struct ConnectionCheckView: View {
    @State private var message = "確認中…"
    @State private var isOK = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: isOK ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")
                .font(.system(size: 56))
                .foregroundStyle(isOK ? .green : .secondary)
            Text(message)
                .multilineTextAlignment(.center)
        }
        .padding()
        // 画面が表示されたときに1回だけ動く(React の useEffect(() => {...}, []) に近い)
        .task {
            await check()
        }
    }

    private func check() async {
        do {
            // days テーブルを1行だけ読んでみる
            try await supabase.from("days").select().limit(1).execute()
            isOK = true
            message = "Supabase につながりました"
        } catch let error as PostgrestError {
            // まだログインしていないので「権限がありません」と断られるのが正常。
            // 断られた=Supabase まで届いている、ということ。
            isOK = true
            message = "Supabase につながりました\n(未ログインなのでデータは読めません。これで正常です)\n\n\(error.message)"
        } catch {
            isOK = false
            message = "つながりませんでした\n\(error.localizedDescription)"
        }
    }
}
