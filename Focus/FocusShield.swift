#if canImport(ManagedSettings)
import FamilyControls
import Foundation
import ManagedSettings

// 実際にスクリーンタイムの制限をかけたり外したりする係(アプリと拡張機能の両方で使う)。

extension ManagedSettingsStore.Name {
    /// このアプリの制限の名前。アプリと拡張機能で同じ名前を使うと、同じ制限を操作できる
    static let study = Self("study")
}

/// 「使ってよいアプリ」の選択の保存場所(App Group。拡張機能からも読めるように)
enum FocusSelectionStore {
    private static let key = "focus.selection"

    static func load() -> FamilyActivitySelection {
        guard let data = AppGroup.defaults.data(forKey: key),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return FamilyActivitySelection() }
        return selection
    }

    static func save(_ selection: FamilyActivitySelection) {
        if let data = try? JSONEncoder().encode(selection) {
            AppGroup.defaults.set(data, forKey: key)
        }
    }
}

enum FocusShield {
    /// 選んだアプリ以外を、すべて制限する
    static func apply() {
        let selection = FocusSelectionStore.load()
        // 安全のため、使ってよいアプリが1つも選ばれていなければ制限しない
        guard !selection.applicationTokens.isEmpty else { return }
        let store = ManagedSettingsStore(named: .study)
        store.shield.applicationCategories = .all(except: selection.applicationTokens)
        store.shield.webDomainCategories = .all(except: selection.webDomainTokens)
    }

    /// 制限を外す
    static func clear() {
        ManagedSettingsStore(named: .study).clearAllSettings()
    }

    /// 記録(FocusFlags)に合わせて、制限をかける/外す
    static func sync(now: Date = Date()) {
        if FocusFlagsStore.load(AppGroup.defaults).shouldShield(now: now) {
            apply()
        } else {
            clear()
        }
    }
}
#endif
