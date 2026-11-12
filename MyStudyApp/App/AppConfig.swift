import Foundation

// Supabase の接続先とキーを読み出す場所。
//
// 値の流れ:
//   Config/Secrets.xcconfig(Git に入らない)
//     → Config/Info.plist の SupabaseHost / SupabaseKey
//       → このファイルで読み出す
enum AppConfig {
    /// Supabase の URL(例: https://abcdefgh.supabase.co)。未設定なら nil。
    static let supabaseURL: URL? = {
        guard let host = normalizeHost(infoString("SupabaseHost")) else { return nil }
        return URL(string: "https://\(host)")
    }()

    /// Supabase の Publishable key。未設定なら nil。
    static let supabaseKey: String? = normalizeKey(infoString("SupabaseKey"))

    /// 接続先とキーの両方が設定されているか
    static var isConfigured: Bool {
        supabaseURL != nil && supabaseKey != nil
    }

    // Info.plist から文字を読む
    private static func infoString(_ key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String) ?? ""
    }

    /// ホスト名の形をととのえる。使えない値なら nil を返す。
    /// (うっかり「https://」を付けたり、見本のまま書き換え忘れたときに気づけるようにする)
    static func normalizeHost(_ raw: String) -> String? {
        var host = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // 「https://」付きで書いてしまった場合は取りのぞく
        for prefix in ["https://", "http://"] where host.hasPrefix(prefix) {
            host.removeFirst(prefix.count)
        }
        // 末尾の「/」を取りのぞく
        while host.hasSuffix("/") { host.removeLast() }

        // 空、見本のまま、「https:」だけ(xcconfig で // 以降が消えた形)は未設定とみなす
        let looksValid = host.contains(".")
            && !host.contains(":")
            && !host.contains(" ")
            && host.allSatisfy { $0.isASCII }
        return looksValid ? host : nil
    }

    /// キーの形をととのえる。使えない値なら nil を返す。
    static func normalizeKey(_ raw: String) -> String? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let looksValid = key.count >= 20 && key.allSatisfy { $0.isASCII && !$0.isWhitespace }
        return looksValid ? key : nil
    }
}
