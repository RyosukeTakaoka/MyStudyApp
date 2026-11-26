import SwiftUI

// 仮眠アラームの画面(右上の … メニューから開く)。
struct NapAlarmView: View {
    let nap: NapAlarm
    @Environment(\.dismiss) private var dismiss
    @AppStorage("nap.minutes") private var minutes = 20

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("決めた時間がたったら、つないでいるイヤホン・ヘッドホンだけで音を鳴らします。スピーカーからは鳴らさず、バイブもしません。")
                        .font(.subheadline)
                }

                NapStatusRows(nap: nap)

                if !nap.isActive {
                    Section("何分寝る?") {
                        Stepper("\(minutes) 分", value: $minutes, in: 5...90, step: 5)
                        HStack {
                            ForEach([10, 15, 20, 25, 30], id: \.self) { value in
                                Button("\(value)") { minutes = value }
                                    .buttonStyle(.bordered)
                                    .tint(minutes == value ? .accentColor : .secondary)
                            }
                        }
                    }
                    Section {
                        Button {
                            nap.start(minutes: minutes)
                        } label: {
                            Label("仮眠を始める", systemImage: "bed.double.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        if !nap.headphonesConnected {
                            Label("イヤホン・ヘッドホンがつながっていません", systemImage: "headphones")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    } footer: {
                        Text("画面を消しても鳴ります(待っているあいだ、無音を流してアプリを起こしておきます)。途中でイヤホンが外れたら、鳴らさずに止めます。")
                    }
                }

                if let message = nap.message {
                    Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("仮眠アラーム")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}

/// 仮眠中・鳴っているときの表示と、止めるボタン(「今日」の画面にも出す)
struct NapStatusRows: View {
    let nap: NapAlarm

    var body: some View {
        switch nap.state {
        case .idle:
            EmptyView()
        case .sleeping(let until):
            Section {
                HStack {
                    Label("仮眠中", systemImage: "bed.double.fill")
                        .font(.headline)
                    Spacer()
                    // style: .timer で、鳴るまでの残り時間が自動で減っていく
                    Text(until, style: .timer)
                        .font(.title3.monospacedDigit().bold())
                }
                Text("\(until.formatted(date: .omitted, time: .shortened)) にイヤホンで鳴らします")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("やめる", role: .destructive) { nap.stop() }
            }
        case .ringing:
            Section {
                Label("起きる時間です", systemImage: "alarm.fill")
                    .font(.title3.bold())
                    .foregroundStyle(.orange)
                HStack {
                    Button {
                        nap.stop()
                    } label: {
                        Text("止める").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        nap.snooze(minutes: 5)
                    } label: {
                        Text("あと5分").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}
