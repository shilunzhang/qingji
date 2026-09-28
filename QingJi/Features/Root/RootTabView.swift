import SwiftUI
import SwiftData
import UIKit

enum AppTab: Hashable {
    case overview, stats, calendar, mine
}

/// 「＋」浮标菜单目标（单一 sheet(item:) 驱动）
enum AddSheet: Identifiable {
    case screenshotImport
    case albumScan
    case cameraCapture
    case manualAdd(kind: TxKind, prefill: AddTransactionView.Mode.Prefill?)

    var id: String {
        switch self {
        case .screenshotImport: return "screenshotImport"
        case .albumScan: return "albumScan"
        case .cameraCapture: return "cameraCapture"
        case .manualAdd(let kind, let prefill):
            return "manualAdd-\(kind.rawValue)-\(prefill?.amountCents.map(String.init) ?? "x")"
        }
    }
}

/// 根框架：4 位 Tab + 右下角浮动记账按钮（文档 §6.1 / v1.4）
struct RootTabView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var appLock = AppLockManager()
    @State private var selection: AppTab = .overview
    @State private var activeSheet: AddSheet?
    @State private var captureHint: String?

    var body: some View {
        TabView(selection: $selection) {
            OverviewView()
                .tabItem { Label("明细", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.overview)

            StatsView()
                .tabItem { Label("图表", systemImage: "chart.pie") }
                .tag(AppTab.stats)

            CalendarView()
                .tabItem { Label("日历", systemImage: "calendar") }
                .tag(AppTab.calendar)

            SettingsView()
                .tabItem { Label("我的", systemImage: "person") }
                .tag(AppTab.mine)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .screenshotImport:
                // v1.4.3：选择器内嵌为 sheet 内容（无内层 sheet，取消一次关闭）
                QuickCaptureView(source: .album)
            case .albumScan:
                NavigationStack {
                    AlbumScanView()
                }
            case .cameraCapture:
                QuickCaptureView(source: .camera)
            case .manualAdd(let kind, let prefill):
                // 修复A：取消/保存在 toolbar 中，必须包 NavigationStack 才能渲染
                NavigationStack {
                    AddTransactionView(mode: .create(kind, prefill))
                }
            }
        }
        .alert("识别提示", isPresented: Binding(
            get: { captureHint != nil },
            set: { if !$0 { captureHint = nil } }
        )) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(captureHint ?? "")
        }
        .overlay {
            // FloatingAddButton 自带全屏收起捕获层与边距，此处不再加 padding
            FloatingAddButton(onSelect: { sheet in
                activeSheet = sheet
            })
        }
        .overlay {
            if appLock.isLocked {
                lockOverlay
            }
        }
        .onChange(of: scenePhase) { _, phase in
            appLock.handleScenePhase(phase)
        }
        .environmentObject(appLock)
        .task {
            // 启动：种子数据 + 周期规则补账（文档 §3.3）
            SeedService.ensureSeeded(context: context)
            let rules = (try? context.fetch(FetchDescriptor<RecurringRule>())) ?? []
            RecurringEngine.postDueRules(rules: rules, context: context)

            // F-13：已授权时静默扫描相册，发现新支付页则弹批量确认（每天至多自动弹一次）
            await AlbumScanModel.shared.scanIfAuthorized()
            if !AlbumScanModel.shared.drafts.isEmpty {
                let lastPrompt = UserDefaults.standard.object(forKey: "qingji.album.lastPrompt") as? Date
                if lastPrompt == nil || Date.now.timeIntervalSince(lastPrompt!) > 86_400 {
                    UserDefaults.standard.set(Date.now, forKey: "qingji.album.lastPrompt")
                    activeSheet = .albumScan
                }
            }
        }
    }

    // MARK: - App 锁

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
