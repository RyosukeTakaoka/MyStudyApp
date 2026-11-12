import SwiftUI

// いちばん外側の画面。状態に応じて、どの画面を出すかを決めます。
struct RootView: View {
    var body: some View {
        if AppConfig.isConfigured {
            ConnectionCheckView()
        } else {
            SetupNeededView()
        }
    }
}

#Preview {
    RootView()
}
