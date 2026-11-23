import Foundation
import Supabase

// Supabase(クラウドのデータベース)との読み書きをまとめた場所。
// 画面のコードから SQL のような細かい話を追い出して、ここだけ見れば通信の内容がわかるようにしています。
//
// 「user_id が自分の行だけ」という条件は書いていません。
// データベース側の RLS が、自動で自分の行だけに絞ってくれるためです。
struct RemoteAPI: Sendable {
    /// from〜to の期間の予定とタスクを読む
    func fetchItems(from: String, to: String) async throws -> [PlanItem] {
        try await supabase
            .from("items")
            .select()
            .gte("date", value: from)   // date >= from
            .lte("date", value: to)     // date <= to
            .execute()
            .value
    }

    /// from〜to の期間の「1日の情報(目標・ふりかえり)」を読む
    func fetchDays(from: String, to: String) async throws -> [DayInfo] {
        try await supabase
            .from("days")
            // 全部の列を読む(目標時間・Claude より は、SQL を実行する前のサーバーには無いので、名前で指定しない)
            .select()
            .gte("date", value: from)
            .lte("date", value: to)
            .execute()
            .value
    }

    /// チェック(done / done_at)と勉強時間の実績(actual_minutes)を保存する
    func updateProgress(id: UUID, done: Bool, doneAt: Date?, actualMinutes: Int?, actualOverride: Int?) async throws {
        try await supabase
            .from("items")
            .update(
                ProgressUpdate(done: done, doneAt: done ? doneAt : nil, actualMinutes: actualMinutes, actualOverride: actualOverride),
                returning: .minimal
            )
            .eq("id", value: id)        // where id = ...
            .execute()
    }

    /// ふりかえりを保存する。その日の行がまだ無ければ作り、あれば reflection だけを書きかえる
    /// (こういう「無ければ追加、あれば更新」を upsert と呼びます)
    func saveReflection(userId: UUID, date: String, reflection: String) async throws {
        try await supabase
            .from("days")
            .upsert(
                ReflectionUpsert(userId: userId, date: date, reflection: reflection),
                onConflict: "user_id,date",   // 「同じ人の同じ日」がすでにあれば更新にする
                returning: .minimal
            )
            .execute()
    }
}

// MARK: - タイマーの記録

extension RemoteAPI {
    /// from〜to の時間にかかっている記録を読む(1日のグラフ用。読むだけ)
    func fetchSessions(from: Date, to: Date) async throws -> [StudySession] {
        let style = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        return try await supabase
            .from("study_sessions")
            .select("id, item_id, item_date, title, subject, started_at, ended_at, end_reason")
            .lt("started_at", value: to.formatted(style))
            .gt("ended_at", value: from.formatted(style))
            .execute()
            .value
    }

    /// 睡眠の予定(その夜の日付が from〜to のもの)。カレンダーへの書き出しにだけ使う
    func fetchSleeps(fromNight: String, toNight: String) async throws -> [SleepPlan] {
        try await supabase
            .from("sleep_plans")
            .select("id, night, start_at, end_at, note")
            .gte("night", value: fromNight)
            .lte("night", value: toNight)
            .execute()
            .value
    }

    func insertSessions(_ sessions: [StudySession]) async throws {
        guard !sessions.isEmpty else { return }
        try await supabase
            .from("study_sessions")
            // ignoreDuplicates: 送り直したときに同じ id があれば、何もしない(二重にならない)
            .upsert(sessions, onConflict: "id", returning: .minimal, ignoreDuplicates: true)
            .execute()
    }
}

// MARK: - 答練・長期の目標

extension RemoteAPI {
    /// 答練(模試)を全部読む
    func fetchExams() async throws -> [ExamResult] {
        try await supabase
            .from("exam_results")
            .select()
            .order("exam_date", ascending: true)
            .execute()
            .value
    }

    /// 答練を入れる・書きかえる(同じ id があれば上書き)
    func saveExam(_ exam: ExamResult) async throws {
        try await supabase
            .from("exam_results")
            .upsert(exam, onConflict: "id", returning: .minimal)
            .execute()
    }

    func deleteExam(id: UUID) async throws {
        try await supabase
            .from("exam_results")
            .delete(returning: .minimal)
            .eq("id", value: id)
            .execute()
    }

    /// 長期の目標(無ければ nil)
    func fetchStudyTarget() async throws -> StudyTarget? {
        let rows: [StudyTarget] = try await supabase
            .from("study_targets")
            .select()
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    /// 月ごとの配分
    func fetchMonthPlans() async throws -> [MonthPlan] {
        try await supabase
            .from("study_month_plans")
            .select("month, planned_hours")
            .order("month", ascending: true)
            .execute()
            .value
    }

    /// その日(日本時間の 0:00)からあとの、鑑定士の勉強時間(分)
    func studyMinutesSince(_ dayKey: String) async throws -> Double {
        try await supabase
            .rpc("study_minutes_since", params: ["p_from": dayKey])
            .execute()
            .value
    }

    /// アプリで測った勉強時間の合計(分。生活の時間はのぞく)
    func studyTotalMinutes() async throws -> Double {
        try await supabase
            .rpc("study_total_minutes")
            .execute()
            .value
    }
}

// MARK: - アプリでの予定の編集

extension RemoteAPI {
    func upsertItems(_ items: [PlanItem]) async throws {
        guard !items.isEmpty else { return }
        try await supabase
            .from("items")
            .upsert(items.map(ItemUpsertRow.init), onConflict: "id", returning: .minimal)
            .execute()
    }

    func deleteItems(ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        try await supabase
            .from("items")
            .delete(returning: .minimal)
            .in("id", values: ids)
            .execute()
    }
}

/// 予定1行をサーバーに送る形。日時は末尾に「Z」を付けた文字にする
private struct ItemUpsertRow: Encodable {
    let item: PlanItem

    enum CodingKeys: String, CodingKey {
        case id, date, kind, title, subject, source, done, note, steps, cautions
        case startTime = "start_time"
        case endTime = "end_time"
        case sortOrder = "sort_order"
        case doneAt = "done_at"
        case actualMinutes = "actual_minutes"
        case actualOverride = "actual_override"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(item.id, forKey: .id)
        try c.encode(item.date, forKey: .date)
        try c.encode(item.kind, forKey: .kind)
        try c.encode(item.startTime, forKey: .startTime)
        try c.encode(item.endTime, forKey: .endTime)
        try c.encode(item.title, forKey: .title)
        try c.encode(item.subject, forKey: .subject)
        try c.encode(item.sortOrder, forKey: .sortOrder)
        try c.encode(item.source, forKey: .source)
        try c.encode(item.done, forKey: .done)
        try c.encode(item.doneAt?.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)), forKey: .doneAt)
        try c.encode(item.actualMinutes, forKey: .actualMinutes)
        try c.encode(item.actualOverride, forKey: .actualOverride)
        try c.encode(item.note, forKey: .note)
        try c.encode(item.steps, forKey: .steps)
        try c.encode(item.cautions, forKey: .cautions)
    }
}

// MARK: - 資料

extension RemoteAPI: NotesAPI {
    func fetchNotes() async throws -> [Note] {
        try await supabase
            .from("notes")
            .select("id, slug, title, category, body_md, pinned, sort_order")
            .execute()
            .value
    }

    /// 本文だけを書きかえる(チェックを押したとき)
    func updateNoteBody(id: UUID, bodyMd: String) async throws {
        try await supabase
            .from("notes")
            .update(["body_md": bodyMd], returning: .minimal)
            .eq("id", value: id)
            .execute()
    }
}

// MARK: - 週次・期間の計画

extension RemoteAPI: PlanBoardAPI {
    /// end_date が from 以降の、期間の計画
    func fetchTermPlans(endingAfter from: String) async throws -> [TermPlan] {
        try await supabase
            .from("term_plans")
            .select("id, title, start_date, end_date, overview_title, stats, overview_note, phases")
            .gte("end_date", value: from)
            .order("start_date")
            .execute()
            .value
    }

    func fetchWeeks(from: String, to: String) async throws -> [WeekPlan] {
        try await supabase
            .from("weeks")
            .select("week_start, label, color, subtitle, events, buffer")
            .gte("week_start", value: from)
            .lte("week_start", value: to)
            .execute()
            .value
    }

    func fetchWeekGoals(from: String, to: String) async throws -> [WeekGoal] {
        try await supabase
            .from("week_goals")
            // 全部の列を読む(箱の名前 box_labels は、SQL を実行する前のサーバーには無いので、名前で指定しない)
            .select()
            .gte("week_start", value: from)
            .lte("week_start", value: to)
            .execute()
            .value
    }

    /// やることの「できた箱」を保存する
    func updateGoalBoxes(id: UUID, doneBoxes: [Int]) async throws {
        try await supabase
            .from("week_goals")
            .update(["done_boxes": doneBoxes], returning: .minimal)
            .eq("id", value: id)
            .execute()
    }

    /// 問題番号の始まりを保存する(nil で消す)
    func updateGoalStart(id: UUID, start: Int?) async throws {
        try await supabase
            .from("week_goals")
            .update(GoalStartUpdate(boxStart: start), returning: .minimal)
            .eq("id", value: id)
            .execute()
    }

    /// 箱の名前(曜日など)を保存する
    func updateGoalLabels(id: UUID, labels: [String]) async throws {
        try await supabase
            .from("week_goals")
            .update(["box_labels": labels], returning: .minimal)
            .eq("id", value: id)
            .execute()
    }
}

/// 問題番号の始まりを送る形(nil も null として送る)
private struct GoalStartUpdate: Encodable {
    let boxStart: Int?
    enum CodingKeys: String, CodingKey { case boxStart = "box_start" }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(boxStart, forKey: .boxStart)
    }
}

/// ふりかえりの保存で送る中身。goal をふくめないので、Claude が書いた目標は消えない
private struct ReflectionUpsert: Encodable {
    let userId: UUID
    let date: String
    let reflection: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case date, reflection
    }
}

/// チェックの更新で送る中身。
/// {"done": true, "done_at": "2026-11-13T07:30:00.000Z", "actual_minutes": 25} のような JSON になる
private struct ProgressUpdate: Encodable {
    let done: Bool
    let doneAt: Date?
    let actualMinutes: Int?
    /// 手で直した実績(null で「タイマーの記録に戻す」)
    let actualOverride: Int?

    enum CodingKeys: String, CodingKey {
        case done
        case doneAt = "done_at"
        case actualMinutes = "actual_minutes"
        case actualOverride = "actual_override"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(done, forKey: .done)
        // 日時は、末尾に「Z」(= 世界標準時)を付けた文字にして送る。
        // タイムゾーンの印が無いと、データベースの設定しだいで時刻がずれて保存されるおそれがあるため。
        // doneAt が nil のときも、省略せずに null として送る(チェックを外したら日時も消すため)
        let text = doneAt?.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        try container.encode(text, forKey: .doneAt)
        try container.encode(actualMinutes, forKey: .actualMinutes)
        try container.encode(actualOverride, forKey: .actualOverride)
    }
}
