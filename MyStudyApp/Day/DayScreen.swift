import SwiftUI
import UIKit

// メインの画面: その日の目標・進み具合・予定・やること を表示します。
struct DayScreen: View {
    let auth: AuthStore
    @State private var store = DayStore()
    @State private var showsSignOutConfirm = false

    var body: some View {
        NavigationStack {
            List {
                if let message = store.errorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                goalSection
                progressSection
                itemSections
            }
            .navigationTitle(DayKey.displayText(store.selectedDate))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("ログアウト", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                            showsSignOutConfirm = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog("ログアウトしますか?", isPresented: $showsSignOutConfirm, titleVisibility: .visible) {
                Button("ログアウト", role: .destructive) {
                    Task { await auth.signOut() }
                }
            }
            // 下に引っぱって更新(プル・トゥ・リフレッシュ)
            .refreshable { await store.load() }
            // 画面が出たときに読み込む
            .task { await store.load() }
        }
    }

    // MARK: - 1日の目標

    @ViewBuilder
    private var goalSection: some View {
        if let goal = store.day?.goal, !goal.isEmpty {
            Section("今日の目標") {
                Text(goal)
                    .font(.headline)
            }
        }
    }

    // MARK: - 進み具合(例: 4/9 完了)

    @ViewBuilder
    private var progressSection: some View {
        if store.totalCount > 0 {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(store.doneCount)/\(store.totalCount) 完了")
                            .font(.headline.monospacedDigit())
                        Spacer()
                        if store.doneCount == store.totalCount {
                            Label("全部おわり!", systemImage: "party.popper")
                                .font(.subheadline)
                                .foregroundStyle(.green)
                        }
                    }
                    ProgressView(value: Double(store.doneCount), total: Double(store.totalCount))
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - 予定とやること

    @ViewBuilder
    private var itemSections: some View {
        if !store.hasLoaded {
            Section {
                HStack {
                    Spacer()
                    ProgressView("読み込み中…")
                    Spacer()
                }
            }
        } else if store.items.isEmpty {
            Section {
                ContentUnavailableView(
                    "予定がありません",
                    systemImage: "calendar.badge.plus",
                    description: Text("Claude に予定を作ってもらうと、ここに表示されます。")
                )
            }
        } else {
            if !store.blocks.isEmpty {
                Section("予定") {
                    ForEach(store.blocks) { item in
                        ItemRow(item: item) { toggle(item) }
                    }
                }
            }
            if !store.tasks.isEmpty {
                Section("やること") {
                    ForEach(store.tasks) { item in
                        ItemRow(item: item) { toggle(item) }
                    }
                }
            }
        }
    }

    private func toggle(_ item: PlanItem) {
        // タップしたときに「コツッ」と軽く振動させる
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task { await store.toggle(item) }
    }
}
