import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case overview, stats, add, calendar, mine
}

/// 根框架：5 位 Tab（中间「＋」为弹层，不驻留）+ App 锁遮罩（文档 §6.1 / F-08）
struct RootTabView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var appLock = AppLockManager()
    @State private var selection: AppTab = .overview
    @State private var lastSelection: AppTab = .overview
    @State private var showAddSheet = false

    var body: some View {
        TabView(selection: $selection) {
            OverviewView()
                .tabItem { Label("明细", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.overview)

            StatsView()
                .tabItem { Label("图表", systemImage: "chart.pie") }
                .tag(AppTab.stats)

            Color.clear
                .tabItem { Label("记账", systemImage: "plus.circle.fill") }
                .tag(AppTab.add)

            CalendarView()
                .tabItem { Label("日历", systemImage: "calendar") }
                .tag(AppTab.calendar)

            SettingsView()
                .tabItem { Label("我的", systemImage: "person") }
                .tag(AppTab.mine)
        }
        .onChange(of: selection) { _, newValue in
            if newValue == .add {
                selection = lastSelection
                showAddSheet = true
            } else {
                lastSelection = newValue
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddTransactionView(mode: .create(.expense))
        }
        .onChange(of: scenePhase) { _, phase in
            appLock.handleScenePhase(phase)
        }
        .overlay {
            if appLock.isLocked {
                lockOverlay
            }
        }
        .environmentObject(appLock)
        .task {
            // 启动：种子数据 + 周期规则补账（文档 §3.3）
            SeedService.ensureSeeded(context: context)
            let rules = (try? context.fetch(FetchDescriptor<RecurringRule>())) ?? []
            RecurringEngine.postDueRules(rules: rules, context: context)
        }
    }

    private var lockOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.circle")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)
                Text("已锁定")
                    .font(.title3.weight(.semibold))
                Button {
                    appLock.unlockManually()
                } label: {
                    Label("解锁", systemImage: "faceid")
                        .font(.headline)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 10)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
        }
    }
}
