import Foundation

// 「予定と実績」の計算(週の表)。画面から分けて、テストできるようにしている。
//   予定 = 勉強の予定ブロックの長さ(開始〜終了)の合計
//   実績 = 勉強の予定の実績(タイマーの記録、または手で直した値)の合計
//   食事・移動などの生活の予定は、どちらにも入れない

/// 1日分
struct PlanActualDay: Identifiable, Equatable {
    var dayKey: String
    var plannedMinutes: Int
    var actualMinutes: Int
    var targetMinutes: Int

    var id: String { dayKey }
    /// 目標時間に対する実績の割合(%)
    var percentOfTarget: Int { targetMinutes > 0 ? Int((Double(actualMinutes) / Double(targetMinutes) * 100).rounded()) : 0 }
}

/// 科目ごと
struct PlanActualSubject: Identifiable, Equatable {
    var subject: String
    var plannedMinutes: Int
    var actualMinutes: Int
    var id: String { subject }
}

struct PlanActualWeek: Equatable {
    var days: [PlanActualDay]
    var subjects: [PlanActualSubject]

    var plannedMinutes: Int { days.reduce(0) { $0 + $1.plannedMinutes } }
    var actualMinutes: Int { days.reduce(0) { $0 + $1.actualMinutes } }
    var targetMinutes: Int { days.reduce(0) { $0 + $1.targetMinutes } }
    var percentOfTarget: Int { targetMinutes > 0 ? Int((Double(actualMinutes) / Double(targetMinutes) * 100).rounded()) : 0 }

    static func build(items: [PlanItem], days: [DayInfo], weekStart: String) -> PlanActualWeek {
        let keys = (0..<7).map { DayKey.adding($0, to: weekStart) }
        let study = items.filter { $0.isStudy && keys.contains($0.date) }

        func planned(_ item: PlanItem) -> Int {
            guard item.isBlock, let start = item.startMinutes, let end = item.endMinutes, end > start else { return 0 }
            return end - start
        }

        let dayRows = keys.map { key in
            let todays = study.filter { $0.date == key }
            let info = days.first { $0.date == key }
            return PlanActualDay(
                dayKey: key,
                plannedMinutes: todays.reduce(0) { $0 + planned($1) },
                actualMinutes: todays.reduce(0) { $0 + ($1.actualMinutes ?? 0) },
                targetMinutes: info?.effectiveTargetMinutes ?? DayInfo.defaultTargetMinutes(for: key)
            )
        }

        var bySubject: [String: (planned: Int, actual: Int)] = [:]
        for item in study {
            var row = bySubject[item.subject] ?? (0, 0)
            row.planned += planned(item)
            row.actual += item.actualMinutes ?? 0
            bySubject[item.subject] = row
        }
        let subjectRows = bySubject
            .map { PlanActualSubject(subject: $0.key, plannedMinutes: $0.value.planned, actualMinutes: $0.value.actual) }
            .filter { $0.plannedMinutes > 0 || $0.actualMinutes > 0 }
            .sorted { ($0.plannedMinutes + $0.actualMinutes, $1.subject) > ($1.plannedMinutes + $1.actualMinutes, $0.subject) }

        return PlanActualWeek(days: dayRows, subjects: subjectRows)
    }
}
