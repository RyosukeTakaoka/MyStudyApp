import Foundation

// 仮眠アラームの音を、その場で作る(音のファイルをアプリに入れなくてよいように)。
// WAV(PCM 16bit・モノラル)の形のデータを作り、AVAudioPlayer で鳴らす。
enum NapSound {
    static let sampleRate = 44_100

    /// 無音(1秒)。待っているあいだ流し続けて、画面を消してもアプリが止まらないようにする
    static func silence(seconds: Double = 1) -> Data {
        wav(samples: [Int16](repeating: 0, count: Int(Double(sampleRate) * seconds)))
    }

    /// アラームの音(1回分。くり返して鳴らす): ピッ・ピッ と短く2回鳴って、少し休む
    static func alarm(frequency: Double = 880) -> Data {
        var samples: [Int16] = []
        func beep(_ seconds: Double) {
            let count = Int(Double(sampleRate) * seconds)
            let fade = Int(Double(sampleRate) * 0.01)   // 音の始まりと終わりを少しだけなめらかに(プツッと鳴らないように)
            for i in 0..<count {
                let envelope = min(1, Double(min(i, count - 1 - i)) / Double(max(fade, 1)))
                let value = sin(2 * Double.pi * frequency * Double(i) / Double(sampleRate)) * envelope * 0.8
                samples.append(Int16(value * Double(Int16.max)))
            }
        }
        func rest(_ seconds: Double) {
            samples += [Int16](repeating: 0, count: Int(Double(sampleRate) * seconds))
        }
        beep(0.15); rest(0.1); beep(0.15); rest(0.6)
        return wav(samples: samples)
    }

    /// 音の数の並びを、WAV のデータにする
    static func wav(samples: [Int16]) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        let byteCount = samples.count * 2
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + byteCount))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16))
        append(UInt16(1))                                   // PCM
        append(UInt16(1))                                   // モノラル
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))                      // 1秒あたりのバイト数
        append(UInt16(2))                                   // 1つの音のバイト数
        append(UInt16(16))                                  // 16bit
        data.append(contentsOf: Array("data".utf8)); append(UInt32(byteCount))
        for sample in samples { append(sample) }
        return data
    }

    /// 音量を少しずつ上げる(鳴り始めてからの秒数 → 0.15〜1.0。20秒で最大)
    static func rampVolume(secondsSinceStart: Double) -> Float {
        Float(min(1.0, 0.15 + 0.85 * max(secondsSinceStart, 0) / 20))
    }
}
