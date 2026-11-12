import SwiftUI
import UIKit

// 「週・月」タブ: 期間の計画(そもそも終わる?・月の流れ)と、週ごとの計画を表示します。
struct PlanBoardScreen: View {
    @State private var store = PlanBoardStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if let problem = store.problem {
                            Label(problem, systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        if !store.hasLoadedOnce {
                            ProgressView("読み込み中…")
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        } else if store.terms.isEmpty && store.sections.isEmpty {
                            ContentUnavailableView(
                                "週・月の計画がありません",
                                systemImage: "calendar.badge.plus",
                                description: Text("Claude に週次・月次の計画を作ってもらうと、ここに表示されます。")
                            )
                        }

                        ForEach(store.terms) { term in
                            TermPlanView(term: term)
                        }

                        ForEach(store.sections) { section in
                            WeekCard(
                                section: section,
                                isCurrent: section.week.weekStart == store.currentWeekStart,
                                onTapBox: { box, goal in
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    store.tapBox(box, of: goal)
                                }
                            )
                            .id(section.id)
                        }
                    }
                    .padding()
                    // iPad や横向きでも読みやすい幅にする
                    .frame(maxWidth: 820)
                    .frame(maxWidth: .infinity)
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle("週・月の計画")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("今週") {
                            withAnimation { proxy.scrollTo(store.currentWeekStart, anchor: .top) }
                        }
                    }
                }
                .refreshable { await store.sync() }
                .task {
                    await store.sync()
                    proxy.scrollTo(store.currentWeekStart, anchor: .top)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await store.sync() } }
                }
            }
        }
    }
}

// MARK: - 期間の計画

private struct TermPlanView: View {
    let term: TermPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(term.title)
                    .font(.title2.bold())
                Text("\(DayKey.shortText(term.startDate))〜\(DayKey.shortText(term.endDate))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // そもそも終わる?
            if !term.stats.isEmpty || term.overviewTitle != nil || term.overviewNote != nil {
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        if let title = term.overviewTitle {
                            Text(title)
                                .font(.headline)
                        }
                        // 幅に合わせて、横に並べる数が自動で変わる
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                            ForEach(Array(term.stats.enumerated()), id: \.offset) { _, stat in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(stat.label)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(stat.value)
                                        .font(.title2.bold())
                                    if let detail = stat.detail {
                                        Text(detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
                                .padding(12)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.secondary.opacity(0.25))
                                }
                            }
                        }
                        if let note = term.overviewNote {
                            Text(note)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // 月の流れ
            if !term.phases.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("月の流れ")
                            .font(.headline)
                        ForEach(Array(term.phases.enumerated()), id: \.offset) { _, phase in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(phase.range)
                                    .font(.caption.bold())
                                    .foregroundStyle(PlanColor.color(phase.color))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .frame(minWidth: 96)
                                    .overlay {
                                        Capsule().stroke(PlanColor.color(phase.color), lineWidth: 1.5)
                                    }
                                Text(phase.text)
                                    .font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 週のカード

private struct WeekCard: View {
    let section: WeekSection
    let isCurrent: Bool
    let onTapBox: (Int, WeekGoal) -> Void

    var body: some View {
        let color = PlanColor.color(section.week.color)
        Card(topColor: color) {
            VStack(alignment: .leading, spacing: 12) {
                // 見出し: 期間・ラベル・できた数
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(section.title)
                            .font(.headline)
                        if let subtitle = section.week.subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let label = section.week.label {
                        Text(label)
                            .font(.caption.bold())
                            .foregroundStyle(color)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .overlay { Capsule().stroke(color, lineWidth: 1.5) }
                    }
                    Text("できた \(section.doneCount)/\(section.totalCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                }
                if isCurrent {
                    Label("今週", systemImage: "star.fill")
                        .font(.caption.bold())
                        .foregroundStyle(color)
                }

                // その週の行事
                if !section.week.events.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(section.week.events.enumerated()), id: \.offset) { _, event in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("•")
                                Text(event)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                // やること(グループごと)
                ForEach(section.groups) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(group.name)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        ForEach(group.goals) { goal in
                            GoalRow(goal: goal) { box in onTapBox(box, goal) }
                            if goal.id != group.goals.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding(.top, 4)
                }

                // バッファのメモ
                if let buffer = section.week.buffer, !buffer.isEmpty {
                    Text(buffer)
                        .font(.footnote)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }
}

/// やること1つ: 題名・説明と、押せる箱
private struct GoalRow: View {
    let goal: WeekGoal
    let onTap: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(goal.title)
                    .font(.subheadline.bold())
                if let detail = goal.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                // 箱が2つ以上あるときは、進み具合を数字でも出す
                if goal.targetCount > 1 {
                    Text("\(goal.doneCount)/\(goal.targetCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(goal.doneCount == goal.targetCount ? Color.green : Color.secondary)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 36, maximum: 40), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(1...goal.targetCount, id: \.self) { box in
                    let done = goal.doneBoxes.contains(box)
                    Button {
                        onTap(box)
                    } label: {
                        Text(goal.targetCount == 1 ? "✓" : "\(box)")
                            .font(.footnote.monospacedDigit())
                            .frame(width: 36, height: 36)
                            .foregroundStyle(done ? Color.white : Color.secondary)
                            .background(done ? Color.green : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(done ? Color.green : Color.secondary.opacity(0.35), lineWidth: 1.5)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(goal.title) \(box)")
                    .accessibilityValue(done ? "できた" : "まだ")
                }
            }
        }
    }
}

// MARK: - 共通の部品

/// 白い角丸のカード(上に色の線を付けられる)
private struct Card<Content: View>: View {
    var topColor: Color? = nil
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .overlay(alignment: .top) {
                if let topColor {
                    Rectangle()
                        .fill(topColor)
                        .frame(height: 4)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.secondary.opacity(0.15))
            }
    }
}

/// 色の名前("blue" など)→ 色
enum PlanColor {
    static func color(_ name: String?) -> Color {
        switch name?.lowercased() {
        case "blue": return .blue
        case "yellow", "orange": return .orange
        case "red": return .red
        case "purple": return .purple
        case "green": return .green
        case "teal": return .teal
        case "pink": return .pink
        default: return .gray
        }
    }
}
