import DeviceActivity
import Foundation

// 集中モードの時間になったら iPhone が起こしてくれる「監視用の拡張機能」。
// アプリを閉じていても、予定の時間に制限をかけ、終わりの時刻に外します。
class FocusMonitorExtension: DeviceActivityMonitor {
    /// 時間帯が始まったとき
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        // 常時ブロックの合図(2027/1/1 0:00 にニコニコ動画を足す)。集中モードとは関係ない
        if activity.rawValue.hasPrefix("permanent.") {
            PermanentBlock.apply()
            return
        }
        guard let end = FocusPlan.endDate(fromName: activity.rawValue) else { return }
        var flags = FocusFlagsStore.load(AppGroup.defaults)
        // 今かかっている時間帯(タイマーなど)のほうが長く続くなら、そちらのまま
        flags.begin(name: activity.rawValue, end: end, now: Date())
        FocusFlagsStore.save(flags, AppGroup.defaults)
        FocusShield.sync()
    }

    /// 時間帯が終わったとき
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        if activity.rawValue.hasPrefix("permanent.") {
            PermanentBlock.apply()   // 外すことはしない(かけ直すだけ)
            return
        }
        var flags = FocusFlagsStore.load(AppGroup.defaults)
        // ほかの集中モードに上書きされていたら、そちらは止めない。
        // 外したあと、まだ続いている自動の時間帯があれば、そちらに切りかえる
        flags.finish(name: activity.rawValue, now: Date(), blocks: FocusBlockStore.load(AppGroup.defaults))
        FocusFlagsStore.save(flags, AppGroup.defaults)
        FocusShield.sync()
    }
}
