#if canImport(ManagedSettings)
import FamilyControls
import Foundation
import ManagedSettings

// 常時ブロック(365日24時間): YouTube・X・Instagram・TikTok・Invidious(と 2027/1/1 からニコニコ動画)を、
// いつでも止めておく。集中モードとは別の制限(名前 "permanent")なので、集中モードを終えても、
// ログアウトしても外れない。アプリの中には、外すボタンを置かない。
// (アプリと、アプリを閉じていても動く監視の拡張機能の両方で使う)

extension ManagedSettingsStore.Name {
    static let permanent = Self("permanent")
}

/// 常時ブロックの保存場所(App Group。拡張機能からも読めるように)
enum PermanentBlockStore {
    private static let appsKey = "permanent.apps"
    private static let niconicoAppsKey = "permanent.niconicoApps"
    private static let invidiousKey = "permanent.invidiousHosts"
    private static let invidiousUpdatedKey = "permanent.invidiousUpdatedAt"
    private static let customKey = "permanent.customDomains"

    /// 自分で足したサイト(足すだけで、外せない)
    static var customDomains: [String] {
        AppGroup.defaults.stringArray(forKey: customKey) ?? []
    }
    static func addCustomDomain(_ host: String) {
        var list = customDomains
        guard !list.contains(host) else { return }
        list.append(host)
        AppGroup.defaults.set(list, forKey: customKey)
    }

    /// 常時ブロックするアプリ(YouTube・X・Instagram・TikTok など。ユーザーが Apple の画面で選ぶ)
    static func apps() -> FamilyActivitySelection { load(appsKey) }
    /// 2027/1/1 から止めるアプリ(ニコニコ動画)
    static func niconicoApps() -> FamilyActivitySelection { load(niconicoAppsKey) }

    /// アプリを足す(外すことはできない: 前に選んだものと合わせる)
    static func addApps(_ selection: FamilyActivitySelection) { add(selection, to: appsKey) }
    static func addNiconicoApps(_ selection: FamilyActivitySelection) { add(selection, to: niconicoAppsKey) }

    static var invidiousHosts: [String] {
        AppGroup.defaults.stringArray(forKey: invidiousKey) ?? []
    }
    static var invidiousUpdatedAt: Date? {
        AppGroup.defaults.object(forKey: invidiousUpdatedKey) as? Date
    }
    static func saveInvidious(_ hosts: [String], at date: Date = Date()) {
        AppGroup.defaults.set(hosts, forKey: invidiousKey)
        AppGroup.defaults.set(date, forKey: invidiousUpdatedKey)
    }

    private static func load(_ key: String) -> FamilyActivitySelection {
        guard let data = AppGroup.defaults.data(forKey: key),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return FamilyActivitySelection() }
        return selection
    }

    private static func add(_ selection: FamilyActivitySelection, to key: String) {
        var merged = load(key)
        merged.applicationTokens.formUnion(selection.applicationTokens)
        merged.webDomainTokens.formUnion(selection.webDomainTokens)
        if let data = try? JSONEncoder().encode(merged) {
            AppGroup.defaults.set(data, forKey: key)
        }
    }
}

enum PermanentBlock {
    /// 今の日付に合わせて、常時ブロックをかける(何回呼んでも同じ。外すことはしない)
    static func apply(now: Date = Date()) {
        let today = DayKey.today(now: now)
        let store = ManagedSettingsStore(named: .permanent)

        // サイト: 名前で止める(Safari などのブラウザで開けなくなる)
        let domains = PermanentBlockList.domains(today: today, invidious: PermanentBlockStore.invidiousHosts,
                                                 custom: PermanentBlockStore.customDomains)
        store.webContent.blockedByFilter = .specific(Set(domains.map { WebDomain(domain: $0) }))

        // アプリ: ユーザーが選んだアプリ(1月1日からはニコニコ動画のアプリも)
        var apps = PermanentBlockStore.apps().applicationTokens
        var webTokens = PermanentBlockStore.apps().webDomainTokens
        if today >= PermanentBlockList.niconicoStartDay {
            apps.formUnion(PermanentBlockStore.niconicoApps().applicationTokens)
            webTokens.formUnion(PermanentBlockStore.niconicoApps().webDomainTokens)
        }
        store.shield.applications = apps.isEmpty ? nil : apps
        store.shield.webDomains = webTokens.isEmpty ? nil : webTokens
    }
}
#endif
