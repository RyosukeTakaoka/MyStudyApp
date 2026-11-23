import SwiftUI

// 終わった日の「勉強した時間帯」の円グラフ。
// 上が 0時(24時)で、時計回りに1日をぐるっと1周します。
// 勉強した時間帯を科目の色で塗り、まん中に日付と合計時間を出します。
struct DayChartSection: View {
    let dayKey: String
    /// これが変わったら読み直す(今日の分を、タイマーを止めるたびに描き直すため)
    var refreshKey: Date? = nil

    @State private var timeline = DayTimeline.empty
    @State private var isLoading = true

    var body: some View {
        Section("この日の勉強") {
            if isLoading && timeline.segments.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if timeline.segments.isEmpty {
                Text("この日のタイマーの記録はありません")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                DayRingChart(dayKey: dayKey, timeline: timeline)
                    .frame(maxWidth: 360)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)

                // 科目ごとの合計
                ForEach(timeline.subjectTotals) { total in
                    HStack {
                        SubjectTag(subject: total.subject)
                        if !total.isStudy {
                            // 生活の時間は、グラフには描くが、まん中の勉強時間には入れない
                            Text("勉強時間に入れない")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(NowNext.durationText(total.minutes))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(total.isStudy ? Color.primary : Color.secondary)
                    }
                }

                // 何時から何時まで勉強したか
                ForEach(timeline.segments) { segment in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle()
                            .fill(SubjectStyle.color(for: segment.subject))
                            .frame(width: 8, height: 8)
                        Text("\(DayTimeline.clock(segment.startMinute))〜\(DayTimeline.clock(segment.endMinute))")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(segment.title)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(segment.minutes)分")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task(id: "\(dayKey)|\(refreshKey?.timeIntervalSince1970 ?? 0)") { await load() }
    }

    /// iPhone に残っている記録を先に出し、サーバーの記録(この機能を入れる前の分など)を足す
    private func load() async {
        isLoading = true
        let local = SessionHistory.shared.sessions(on: dayKey)
        timeline = DayTimeline.build(sessions: local, dayKey: dayKey)
        if let start = DayKey.date(dayKey: dayKey, minutes: 0),
           let end = DayKey.date(dayKey: DayKey.adding(1, to: dayKey), minutes: 0),
           let remote = try? await RemoteAPI().fetchSessions(from: start, to: end) {
            // 同じ記録は id で1つにまとめられる
            timeline = DayTimeline.build(sessions: local + remote, dayKey: dayKey)
        }
        isLoading = false
    }
}

/// 24時間の円グラフ本体
struct DayRingChart: View {
    let dayKey: String
    let timeline: DayTimeline

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let outer = size / 2 - 22            // 外側に時刻の数字を書く分あける
            let inner = outer * 0.48
            let laneWidth = (outer - inner) / CGFloat(timeline.laneCount)

            ZStack {
                // 1日ぶんの、うすい灰色の輪
                ringPath(center: center, inner: inner, outer: outer, from: 0, to: 1440)
                    .fill(Color.secondary.opacity(0.12))

                // 1時間ごとの細い線
                ForEach(0..<24, id: \.self) { hour in
                    Path { path in
                        let angle = Self.angle(minute: Double(hour * 60))
                        path.move(to: Self.point(center: center, radius: inner, angle: angle))
                        path.addLine(to: Self.point(center: center, radius: outer, angle: angle))
                    }
                    .stroke(Color.secondary.opacity(hour % 6 == 0 ? 0.35 : 0.15), lineWidth: hour % 6 == 0 ? 1 : 0.5)
                }

                // 勉強した時間帯(科目の色)
                ForEach(timeline.segments) { segment in
                    let laneOuter = outer - CGFloat(segment.lane) * laneWidth
                    let laneInner = laneOuter - laneWidth
                    ringPath(center: center, inner: laneInner, outer: laneOuter,
                             from: segment.startMinute, to: segment.endMinute)
                        .fill(SubjectStyle.color(for: segment.subject).opacity(0.85))
                        .overlay {
                            ringPath(center: center, inner: laneInner, outer: laneOuter,
                                     from: segment.startMinute, to: segment.endMinute)
                                .stroke(Color(uiColor: .systemBackground), lineWidth: 1.5)
                        }
                }

                // 長い区間には、題名を書く
                ForEach(timeline.segments.filter { $0.endMinute - $0.startMinute >= 45 }) { segment in
                    let laneOuter = outer - CGFloat(segment.lane) * laneWidth
                    let mid = (segment.startMinute + segment.endMinute) / 2
                    Text(String(segment.title.prefix(6)))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 1)
                        .position(Self.point(center: center, radius: laneOuter - laneWidth / 2, angle: Self.angle(minute: mid)))
                }

                // 外側の時刻(1〜24)
                ForEach(1...24, id: \.self) { hour in
                    Text("\(hour)")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .position(Self.point(center: center, radius: outer + 12, angle: Self.angle(minute: Double(hour * 60))))
                }

                // まん中: 日付と合計
                VStack(spacing: 2) {
                    Text(DayKey.shortText(dayKey))
                        .font(.subheadline.bold())
                    Text(NowNext.durationText(timeline.totalMinutes))
                        .font(.title3.bold().monospacedDigit())
                    Text("勉強")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .position(center)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(DayKey.displayText(dayKey))の勉強 合計\(NowNext.durationText(timeline.totalMinutes))")
    }

    /// 0時からの分数 → 角度(上が 0時、時計回り)
    static func angle(minute: Double) -> Angle {
        .degrees(minute / 1440 * 360 - 90)
    }

    static func point(center: CGPoint, radius: CGFloat, angle: Angle) -> CGPoint {
        CGPoint(x: center.x + radius * CGFloat(cos(angle.radians)),
                y: center.y + radius * CGFloat(sin(angle.radians)))
    }

    /// 輪の一部(ドーナツのかけら)の形
    private func ringPath(center: CGPoint, inner: CGFloat, outer: CGFloat, from: Double, to: Double) -> Path {
        Path { path in
            let start = Self.angle(minute: from)
            let end = Self.angle(minute: to)
            // SwiftUI では、clockwise: false が画面の上で時計回りになる
            path.addArc(center: center, radius: outer, startAngle: start, endAngle: end, clockwise: false)
            path.addArc(center: center, radius: inner, startAngle: end, endAngle: start, clockwise: true)
            path.closeSubpath()
        }
    }
}
