import Foundation
import Observation

// 答練の一覧を読み書きする係。読んだものは端末にも取っておき、電波が無くても見られるようにする。
// 書きこみ(足す・直す・消す)は、電波があるときだけ(失敗したら、その理由を出す)。
@MainActor
@Observable
final class ExamStore {
    private(set) var exams: [ExamResult] = []
    private(set) var hasLoadedOnce = false
    private(set) var problem: String?

    private let fileURL: URL?

    init(fileURL: URL? = ExamStore.defaultFileURL) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([ExamResult].self, from: data) {
            exams = saved
            hasLoadedOnce = true
        }
    }

    nonisolated static var defaultFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("exams.json")
    }

    nonisolated static func clearSaved() {
        if let url = defaultFileURL { try? FileManager.default.removeItem(at: url) }
    }

    /// これからの答練(日付の近い順)
    func upcoming(today: String) -> [ExamResult] {
        exams.filter { $0.isUpcoming && $0.examDate >= today }
            .sorted { ($0.examDate, $0.startTime ?? "") < ($1.examDate, $1.startTime ?? "") }
    }

    /// 受けた答練(新しい順)。科目ごとにまとめる
    func pastBySubject(today: String) -> [ExamGroup] {
        let past = exams.filter { !$0.isUpcoming || $0.examDate < today }
        let subjects = Array(Set(past.map(\.subject))).sorted()
        return subjects.map { subject in
            ExamGroup(subject: subject, exams: past.filter { $0.subject == subject }.sorted { $0.examDate > $1.examDate })
        }
    }

    func sync() async {
        do {
            exams = try await RemoteAPI().fetchExams()
            hasLoadedOnce = true
            problem = nil
            save()
        } catch {
            problem = "答練を読みこめませんでした(前に読んだものを表示しています)。"
        }
    }

    /// 足す・直す。うまくいけば true
    func save(_ exam: ExamResult) async -> Bool {
        do {
            try await RemoteAPI().saveExam(exam)
            if let index = exams.firstIndex(where: { $0.id == exam.id }) {
                exams[index] = exam
            } else {
                exams.append(exam)
            }
            problem = nil
            save()
            return true
        } catch {
            problem = "保存できませんでした。電波を確かめてください。同じ日・科目・名前の答練がすでにあると保存できません。"
            return false
        }
    }

    func delete(_ exam: ExamResult) async -> Bool {
        do {
            try await RemoteAPI().deleteExam(id: exam.id)
            exams.removeAll { $0.id == exam.id }
            problem = nil
            save()
            return true
        } catch {
            problem = "消せませんでした。電波を確かめてください。"
            return false
        }
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(exams) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// 科目ごとの答練のまとまり
struct ExamGroup: Identifiable, Equatable {
    var subject: String
    var exams: [ExamResult]
    var id: String { subject }
}
