import Charts
import SwiftUI

// 「答練」タブ: これからの答練・点数の推移(科目ごとのグラフ)・受けた答練と振り返り。
struct ExamsScreen: View {
    let store: ExamStore
    @State private var editing: ExamResult?
    @State private var showsAdd = false
    @Environment(\.scenePhase) private var scenePhase

    private var today: String { DayKey.today(now: Date()) }

    var body: some View {
        NavigationStack {
            List {
                if let problem = store.problem {
                    Section {
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if store.hasLoadedOnce && store.exams.isEmpty {
                    ContentUnavailableView(
                        "答練の記録がありません",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("右上の + で足すか、Claude に答練の予定・成績を入れてもらうと、ここに出ます。")
                    )
                }

                let upcoming = store.upcoming(today: today)
                if !upcoming.isEmpty {
                    Section("これからの答練") {
                        ForEach(upcoming) { exam in
                            NavigationLink(value: exam.id) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(exam.title).font(.subheadline.bold())
                                    Text("\(exam.whenText) ・ \(exam.subject)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                let scored = store.exams.filter { $0.scoreForChart != nil }
                if scored.count >= 1 {
                    Section {
                        ScoreChart(exams: scored)
                            .frame(height: 220)
                            .padding(.vertical, 6)
                    } header: {
                        Text("点数の推移")
                    } footer: {
                        Text("満点が入っている答練は、満点に対する%で描いています。")
                    }
                }

                ForEach(store.pastBySubject(today: today)) { group in
                    Section(group.subject) {
                        ForEach(group.exams) { exam in
                            NavigationLink(value: exam.id) {
                                ExamRow(exam: exam)
                            }
                        }
                    }
                }
            }
            .navigationTitle("答練")
            .navigationDestination(for: UUID.self) { id in
                ExamDetailScreen(store: store, examId: id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("答練を足す")
                }
            }
            .sheet(isPresented: $showsAdd) {
                ExamEditorSheet(store: store, original: nil)
            }
            .refreshable { await store.sync() }
            .task { await store.sync() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await store.sync() } }
            }
        }
    }
}

/// 一覧の1行
private struct ExamRow: View {
    let exam: ExamResult

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(exam.title).font(.subheadline.bold())
                Spacer()
                Text(DayKey.shortText(exam.examDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !exam.scoreText.isEmpty {
                Text(exam.scoreText)
                    .font(.caption.monospacedDigit())
            }
            if let missed = exam.missedPoints, !missed.isEmpty {
                Text("論点漏れ: \(missed)")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
    }
}

/// 科目ごとの点数の推移(折れ線)
private struct ScoreChart: View {
    let exams: [ExamResult]

    var body: some View {
        Chart {
            ForEach(exams) { exam in
                if let date = DayKey.date(dayKey: exam.examDate, minutes: 12 * 60), let value = exam.scoreForChart {
                    LineMark(x: .value("日付", date), y: .value("点数", value))
                        .foregroundStyle(by: .value("科目", exam.subject))
                    PointMark(x: .value("日付", date), y: .value("点数", value))
                        .foregroundStyle(by: .value("科目", exam.subject))
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month().day())
            }
        }
    }
}

/// 答練1回分の中身(振り返りつき)
struct ExamDetailScreen: View {
    let store: ExamStore
    let examId: UUID
    @State private var showsEdit = false
    @State private var confirmsDelete = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let exam = store.exams.first(where: { $0.id == examId }) {
            List {
                Section {
                    LabeledContent("日時", value: exam.whenText)
                    LabeledContent("科目", value: exam.subject)
                    if !exam.scoreText.isEmpty {
                        LabeledContent("成績", value: exam.scoreText)
                    } else {
                        Text("まだ点数がありません(受けたら「直す」で入れます)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                textSection("良かった点", exam.goodPoints, color: .green)
                textSection("論点漏れ・できなかった点", exam.missedPoints, color: .orange)
                textSection("次にやること", exam.nextActions, color: .blue)
                textSection("メモ", exam.note, color: .secondary)
                Section {
                    Button("この答練を消す", role: .destructive) { confirmsDelete = true }
                }
            }
            .navigationTitle(exam.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("直す") { showsEdit = true }
                }
            }
            .sheet(isPresented: $showsEdit) {
                ExamEditorSheet(store: store, original: exam)
            }
            .confirmationDialog("この答練を消しますか?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("消す", role: .destructive) {
                    Task {
                        if await store.delete(exam) { dismiss() }
                    }
                }
            }
        } else {
            ContentUnavailableView("この答練は消されました", systemImage: "doc.text")
        }
    }

    @ViewBuilder
    private func textSection(_ title: String, _ text: String?, color: Color) -> some View {
        if let text, !text.isEmpty {
            Section {
                Text(text)
                    .textSelection(.enabled)
            } header: {
                Text(title).foregroundStyle(color)
            }
        }
    }
}

/// 答練を足す・直す画面
struct ExamEditorSheet: View {
    let store: ExamStore
    let original: ExamResult?

    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var hasTime = false
    @State private var time = Date()
    @State private var subject = "鑑定理論"
    @State private var title = ""
    @State private var score = ""
    @State private var fullScore = ""
    @State private var average = ""
    @State private var rank = ""
    @State private var examinees = ""
    @State private var goodPoints = ""
    @State private var missedPoints = ""
    @State private var nextActions = ""
    @State private var note = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("答練") {
                    TextField("名前(例: 応用答練 第4回)", text: $title)
                    Picker("科目", selection: $subject) {
                        ForEach(ItemDraft.subjects(including: subject), id: \.self) { Text($0).tag($0) }
                    }
                    DatePicker("日付", selection: $date, displayedComponents: .date)
                    Toggle("始まる時刻", isOn: $hasTime)
                    if hasTime {
                        DatePicker("時刻", selection: $time, displayedComponents: .hourAndMinute)
                    }
                }
                Section {
                    numberField("点数", $score)
                    numberField("満点", $fullScore)
                    numberField("平均点", $average)
                    numberField("順位", $rank)
                    numberField("受験者数", $examinees)
                } header: {
                    Text("成績")
                } footer: {
                    Text("まだ受けていない答練は、点数を空のままにすると「これからの答練」に出ます。")
                }
                Section("振り返り") {
                    TextField("良かった点", text: $goodPoints, axis: .vertical).lineLimit(2...6)
                    TextField("論点漏れ・できなかった点", text: $missedPoints, axis: .vertical).lineLimit(2...6)
                    TextField("次にやること", text: $nextActions, axis: .vertical).lineLimit(2...6)
                    TextField("メモ", text: $note, axis: .vertical).lineLimit(1...4)
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle(original == nil ? "答練を足す" : "答練を直す")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func numberField(_ label: String, _ text: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("—", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
        }
    }

    private func load() {
        guard let exam = original else { return }
        title = exam.title
        subject = exam.subject
        date = DayKey.date(dayKey: exam.examDate, minutes: 12 * 60) ?? Date()
        if let minutes = TimeOfDay.minutes(from: exam.startTime) {
            hasTime = true
            time = DayKey.date(dayKey: exam.examDate, minutes: minutes) ?? Date()
        }
        func text(_ v: Double?) -> String { v.map { $0.rounded() == $0 ? String(Int($0)) : String($0) } ?? "" }
        score = text(exam.score)
        fullScore = text(exam.fullScore)
        average = text(exam.average)
        rank = exam.rank.map(String.init) ?? ""
        examinees = exam.examinees.map(String.init) ?? ""
        goodPoints = exam.goodPoints ?? ""
        missedPoints = exam.missedPoints ?? ""
        nextActions = exam.nextActions ?? ""
        note = exam.note ?? ""
    }

    private func save() async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "名前を入れてください。"
            return
        }
        func number(_ s: String) -> Double? { Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) }
        func integer(_ s: String) -> Int? { Int(s.trimmingCharacters(in: .whitespaces)) }
        func textOrNil(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        let minutes = DayKey.minutesOfDay(time)
        let exam = ExamResult(
            id: original?.id ?? UUID(),
            examDate: DayKey.today(now: date),
            startTime: hasTime ? String(format: "%02d:%02d:00", minutes / 60, minutes % 60) : nil,
            subject: subject, title: trimmed,
            score: number(score), fullScore: number(fullScore), average: number(average),
            rank: integer(rank), examinees: integer(examinees),
            goodPoints: textOrNil(goodPoints), missedPoints: textOrNil(missedPoints),
            nextActions: textOrNil(nextActions), note: textOrNil(note),
            source: original?.source ?? "app"
        )
        isSaving = true
        defer { isSaving = false }
        if await store.save(exam) {
            dismiss()
        } else {
            errorMessage = store.problem
        }
    }
}
