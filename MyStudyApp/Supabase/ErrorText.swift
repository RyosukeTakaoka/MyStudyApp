import Foundation
import Supabase

// エラーを、画面に出せる文にする道具。
enum ErrorText {
    /// 電波がない・つながらない、という種類のエラーか
    static func isNetworkError(_ error: Error) -> Bool {
        error is URLError || (error as NSError).domain == NSURLErrorDomain
    }

    /// 画面に出す説明文を作る
    static func message(for error: Error) -> String {
        // データベース(PostgREST)が返したエラーは、中の message がいちばん分かりやすい
        // 例: "permission denied for table items"
        if let dbError = error as? PostgrestError {
            var text = dbError.message
            if let code = dbError.code { text += "(コード: \(code))" }
            if let hint = dbError.hint { text += "\n\(hint)" }
            return text
        }
        return error.localizedDescription
    }
}
