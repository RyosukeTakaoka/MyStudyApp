import SwiftUI

// 科目ごとの色。知らない科目名が来たときはグレーで表示します
// (データベース側で科目を増やしても、アプリを直さずに済むようにするため)。
enum SubjectStyle {
    static func color(for subject: String) -> Color {
        switch subject {
        case "鑑定理論": return .blue
        case "行政法規": return .teal
        case "民法": return .orange
        case "経済": return .green
        case "会計": return .purple
        case "学校": return .pink
        default: return .gray
        }
    }
}

/// 科目名の小さなラベル
struct SubjectTag: View {
    let subject: String

    var body: some View {
        let color = SubjectStyle.color(for: subject)
        Text(subject)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }
}
