import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppState
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            TodayView()
                .tabItem {
                    Label("今日", systemImage: "sun.max")
                }
                .tag(0)

            TrendsView()
                .tabItem {
                    Label("趋势", systemImage: "chart.xyaxis.line")
                }
                .tag(1)

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "slider.horizontal.3")
                }
                .tag(2)
        }
        .background(Theme.background)
        .alert("出错了", isPresented: Binding(
            get: { app.errorMessage != nil },
            set: { if !$0 { app.errorMessage = nil } }
        )) {
            Button("好") { app.errorMessage = nil }
        } message: {
            Text(app.errorMessage ?? "")
        }
    }
}
