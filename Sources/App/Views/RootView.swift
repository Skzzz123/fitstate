import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.scenePhase) private var scenePhase
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
        // 快捷指令是在 App 的后台进程里写数据的，写完发的通知如果 App 当时
        // 没在运行就收不到。所以每次回到前台都重新读一遍文件，
        // 否则界面还停在旧数据上，看起来就像「数据写不进去」。
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await app.refresh() }
            }
        }
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
