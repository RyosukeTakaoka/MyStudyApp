import Foundation
import Network
import Observation

// 電波(ネットワーク)がつながっているかを見張る係。
// つながった瞬間に同期を走らせるために使います。
@MainActor
@Observable
final class NetworkMonitor {
    /// 今つながっているか
    private(set) var isOnline = true

    private let monitor = NWPathMonitor()
    private var hasStarted = false

    /// 見張りを始める(2回呼んでも、始めるのは1回だけ)
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        // つながり方が変わるたびに、ここが呼ばれる
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                self?.isOnline = online
            }
        }
        monitor.start(queue: DispatchQueue(label: "NetworkMonitor"))
    }
}
