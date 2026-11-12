#if canImport(AppIntents)
import AppIntents
import Foundation

// ウィジェットのチェックボタンを押したときに動く処理。
// アプリを開かずにチェックでき、記録はアプリを次に開いたときにサーバーへ送られます。
struct ToggleItemIntent: AppIntent {
    static var title: LocalizedStringResource = "予定をチェック"
    static var isDiscoverable: Bool = false

    @Parameter(title: "予定のID")
    var itemId: String

    init() {}

    init(itemId: UUID) {
        self.itemId = itemId.uuidString
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: itemId) {
            SharedStore.toggleFromWidget(itemId: id, now: Date())
        }
        // ここで終わると、WidgetKit が自動でウィジェットを描き直す
        return .result()
    }
}
#endif
