import DeviceActivity
import Foundation

// 集中モードの時間になったら iPhone が起こしてくれる「監視用の拡張機能」。
// アプリを閉じていても、予定の時間に制限をかけ、終わりの時刻に外します。
class FocusMonitorExtension: DeviceActivityMonitor {
    /// 時間帯が始まったとき
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        guard let end = FocusPlan.endDate(fromName: activity.rawValue) else { return }
        var flags = FocusFlagsStore.load(AppGroup.defaults)
        flags.windowEnd = end
        flags.windowName = activity.rawValue
        FocusFlagsStore.save(flags, AppGroup.defaults)
        FocusShield.sync()
    }

    /// 時間帯が終わったとき
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        var flags = FocusFlagsStore.load(AppGroup.defaults)
        // ほかの集中モードに上書きされていたら、そちらは止めない
        if flags.windowName == activity.rawValue {
            flags.windowEnd = nil
            flags.windowName = nil
            FocusFlagsStore.save(flags, AppGroup.defaults)
        }
        FocusShield.sync()
    }
}
