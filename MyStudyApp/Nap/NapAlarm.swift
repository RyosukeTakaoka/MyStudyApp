import AVFoundation
import Observation
import UIKit

// 仮眠アラーム: 決めた時間がたったら、つないでいるイヤホン・ヘッドホンだけで音を鳴らす(バイブなし)。
//   ・スピーカーからは鳴らさない(始めるときにイヤホンが無ければ始めない。途中で外れたら、鳴らさずに止める)
//   ・待っているあいだは無音を流し続ける(画面を消しても、アプリが止まらないようにするため。Info.plist の「audio」)
//   ・鳴るときは、小さい音から少しずつ大きくする
@MainActor
@Observable
final class NapAlarm {
    enum State: Equatable {
        case idle
        case sleeping(until: Date)
        case ringing
    }

    private(set) var state: State = .idle
    /// 最後のお知らせ(イヤホンが外れて止めた、など)
    private(set) var message: String?

    private var silencePlayer: AVAudioPlayer?
    private var alarmPlayer: AVAudioPlayer?
    private var ticker: Timer?
    private var ringStartedAt: Date?
    private var observers: [NSObjectProtocol] = []

    var isActive: Bool { state != .idle }

    /// 今、イヤホン・ヘッドホンがつながっているか
    var headphonesConnected: Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { Self.headphonePorts.contains($0.portType) }
    }

    private static let headphonePorts: Set<AVAudioSession.Port> = [
        .headphones, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP, .usbAudio,
    ]

    /// 仮眠を始める(minutes 分後に鳴る)。イヤホンが無ければ始めない
    func start(minutes: Int, now: Date = Date()) {
        stop(silently: true)
        message = nil
        guard headphonesConnected else {
            message = "イヤホン・ヘッドホンをつないでから始めてください(スピーカーからは鳴らしません)。"
            return
        }
        let session = AVAudioSession.sharedInstance()
        do {
            // .playback: 消音スイッチがオンでも鳴る。ほかのアプリの音(音楽など)は止めずに混ぜる
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            silencePlayer = try AVAudioPlayer(data: NapSound.silence())
            silencePlayer?.numberOfLoops = -1
            silencePlayer?.volume = 0
            silencePlayer?.play()
        } catch {
            message = "音の準備ができませんでした: \(error.localizedDescription)"
            return
        }
        state = .sleeping(until: now.addingTimeInterval(TimeInterval(minutes * 60)))
        observeAudio()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    /// 止める(鳴っている音も、待っている途中も)
    func stop(silently: Bool = false) {
        ticker?.invalidate()
        ticker = nil
        silencePlayer?.stop()
        silencePlayer = nil
        alarmPlayer?.stop()
        alarmPlayer = nil
        ringStartedAt = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        if state != .idle {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        state = .idle
        if !silently { message = nil }
    }

    /// あと少し寝る(鳴っているのを止めて、minutes 分後にまた鳴らす)
    func snooze(minutes: Int = 5) {
        start(minutes: minutes)
    }

    // MARK: - 中の動き

    private func tick(now: Date = Date()) {
        switch state {
        case .sleeping(let until) where now >= until:
            ring()
        case .ringing:
            if let started = ringStartedAt {
                alarmPlayer?.volume = NapSound.rampVolume(secondsSinceStart: now.timeIntervalSince(started))
            }
        default:
            break
        }
    }

    private func ring() {
        // 鳴らす前に、もう一度イヤホンを確かめる(外れていたら、スピーカーから鳴らさないように止める)
        guard headphonesConnected else {
            stop(silently: true)
            message = "イヤホン・ヘッドホンが外れていたので、鳴らさずに止めました。"
            return
        }
        do {
            let player = try AVAudioPlayer(data: NapSound.alarm())
            player.numberOfLoops = -1
            player.volume = NapSound.rampVolume(secondsSinceStart: 0)
            player.play()
            alarmPlayer = player
            ringStartedAt = Date()
            state = .ringing
        } catch {
            stop(silently: true)
            message = "アラームを鳴らせませんでした: \(error.localizedDescription)"
        }
    }

    /// イヤホンが外れた・電話がかかってきた、などに合わせる
    private func observeAudio() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor in
                guard let self, raw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue,
                      !self.headphonesConnected else { return }
                // イヤホンが外れた: スピーカーから鳴らないように止める
                self.stop(silently: true)
                self.message = "イヤホン・ヘッドホンが外れたので、仮眠アラームを止めました。"
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor in
                // 電話などで止められたあと、続きを流し直す(待っている途中も、鳴っている途中も)
                guard let self, raw == AVAudioSession.InterruptionType.ended.rawValue, self.isActive else { return }
                try? AVAudioSession.sharedInstance().setActive(true)
                self.silencePlayer?.play()
                self.alarmPlayer?.play()
            }
        })
    }
}
