import Foundation

// アプリとウィジェットが共有する「App Group」(共有フォルダ)の情報。
// ウィジェットは別のプログラムとして動くので、アプリのデータを直接は読めません。
// そこで、両方から見える共有フォルダにデータを置いて受け渡しします。
//
// グループの名前は Config/Config.xcconfig の APP_GROUP_ID で決め、Info.plist 経由で読みます。
enum AppGroup {
    static let id: String = (Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String) ?? ""

    /// 共有フォルダの場所(App Group の設定がまだなら nil)
    static var containerURL: URL? {
        guard !id.isEmpty else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }

    /// 共有の UserDefaults(小さな設定値の受け渡しに使う)
    static var defaults: UserDefaults {
        UserDefaults(suiteName: id) ?? .standard
    }
}
