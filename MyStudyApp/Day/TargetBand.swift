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
                    ProgressView(value: min(data.totalHours, goal), total: max(goal, 1))
                        .tint(.green)
                }
            }
            .padding(.vertical, 2)
        }
    }
}
