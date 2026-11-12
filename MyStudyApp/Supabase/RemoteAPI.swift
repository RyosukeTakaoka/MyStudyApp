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
            .select("date, goal, reflection")
            .gte("date", value: from)
            .lte("date", value: to)
            .execute()
            .value
    }

    /// チェックを付ける/外す
    func setDone(id: UUID, done: Bool, doneAt: Date?) async throws {
        try await supabase
            .from("items")
            .update(DoneUpdate(done: done, doneAt: done ? doneAt : nil), returning: .minimal)
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

/// チェックの更新で送る中身。 {"done": true, "done_at": "2026-11-13T07:30:00.000Z"} のような JSON になる
private struct DoneUpdate: Encodable {
    let done: Bool
    let doneAt: Date?

    enum CodingKeys: String, CodingKey {
        case done
        case doneAt = "done_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(done, forKey: .done)
        // 日時は、末尾に「Z」(= 世界標準時)を付けた文字にして送る。
        // タイムゾーンの印が無いと、データベースの設定しだいで時刻がずれて保存されるおそれがあるため。
        // doneAt が nil のときも、省略せずに null として送る(チェックを外したら日時も消すため)
        let text = doneAt?.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        try container.encode(text, forKey: .doneAt)
    }
}
