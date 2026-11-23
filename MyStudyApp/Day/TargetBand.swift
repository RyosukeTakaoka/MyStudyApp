import Observation
import SwiftUI

// 「今日」タブのいちばん上の小さな帯:
//   論文式試験まで ○日 ・ 次の答練 ・ 累計 ○時間 / 3000時間
// 中身はサーバー(study_targets・exam_results・勉強時間の合計)から読み、端末にも取っておく。
@MainActor
@Observable
final class TargetBandStore {
    private(set) var data: TargetBandData?
    private static let key = "targetBand.data"

    init() {
        if let saved = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(TargetBandData.self, from: saved) {
            data = decoded
        }
    }

    static func clearSaved() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// サーバーから読み直す(読めなかったものは、前の値のまま)
    func refresh(today: String) async {
        let api = RemoteAPI()
        let target = (try? await api.fetchStudyTarget()) ?? nil
        let minutes = try? await api.studyTotalMinutes()
        let exams = try? await api.fetchExams()
        var next = data ?? TargetBandData(target: .fallback, studyMinutes: 0, nextExam: nil)
        if let target { next.target = target }
        if let minutes { next.studyMinutes = minutes }
        if let exams { next.nextExam = TargetBandData.nextExam(in: exams, today: today) }
        // 1つも読めなかったら(電波が無い・SQL がまだ)、何も変えない
        guard target != nil || minutes != nil || exams != nil else { return }
        data = next
        if let encoded = try? JSONEncoder().encode(next) {
            UserDefaults.standard.set(encoded, forKey: Self.key)
        }
    }
}

/// 帯の見た目
struct TargetBandSection: View {
    let data: TargetBandData
    let today: String

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    if let days = data.daysLeft(from: today), let date = data.target.targetDate {
                        Text("\(data.target.targetName)まで")
                            .font(.subheadline)
                        Text("\(max(days, 0))日")
                            .font(.title3.bold().monospacedDigit())
                        Text("(\(DayKey.shortText(date)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(data.target.targetName)
                            .font(.subheadline)
                    }
                    Spacer(minLength: 0)
                }
                if let exam = data.nextExam {
                    Label("次の答練: \(exam.whenText) \(exam.title)", systemImage: "pencil.and.list.clipboard")
                        .font(.caption)
                        .lineLimit(1)
                }
                VStack(alignment: .leading, spacing: 3) {
                    let goal = Double(data.target.totalHoursGoal)
                    HStack {
                        Text("累計 \(Int(data.totalHours))時間 / \(data.target.totalHoursGoal)時間")
                            .font(.caption.monospacedDigit())
                        Spacer()
                        Text("\(Int((data.totalHours / max(goal, 1) * 100).rounded()))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    HoursBar(total: data.totalHours, goal: goal, ticks: data.monthTicks(today: today))
                    if let perMonth = data.hoursPerMonth(today: today), perMonth > 0, let date = data.target.targetDate {
                        Text("\(DayKey.shortText(date))まで 月あたり 約\(Int(perMonth.rounded()))時間(目盛りは、同じペースで進んだときの各月の始まりの位置)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

/// 累計時間のバー。月の始まりごとに目盛り(同じペースで進んだら、その月の始まりにここまで来ている位置)を入れる
private struct HoursBar: View {
    let total: Double
    let goal: Double
    let ticks: [MonthTick]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.18))
                    Capsule().fill(Color.green)
                        .frame(width: width * fraction(total))
                    ForEach(ticks) { tick in
                        Rectangle()
                            .fill(Color.primary.opacity(0.55))
                            .frame(width: 1.5, height: 12)
                            .offset(x: width * fraction(tick.hours) - 0.75)
                    }
                }
                .frame(height: 8)
                .frame(maxHeight: .infinity)
            }
            .frame(height: 12)
            // 目盛りの下に月(重なりすぎないよう、せまいときは1つおき)
            GeometryReader { geometry in
                let width = geometry.size.width
                let step = ticks.count > 1 && width / CGFloat(ticks.count) < 22 ? 2 : 1
                ZStack(alignment: .topLeading) {
                    ForEach(Array(ticks.enumerated()), id: \.element.id) { index, tick in
                        if index % step == 0 || index == ticks.count - 1 {
                            Text("\(tick.month)月")
                                .font(.system(size: 9).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .fixedSize()
                                .position(x: min(max(width * fraction(tick.hours), 10), width - 10), y: 6)
                        }
                    }
                }
            }
            .frame(height: ticks.isEmpty ? 0 : 12)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("累計 \(Int(total))時間 / \(Int(goal))時間")
    }

    private func fraction(_ hours: Double) -> CGFloat {
        CGFloat(min(max(hours / max(goal, 1), 0), 1))
    }
}
