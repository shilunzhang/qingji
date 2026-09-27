import SwiftUI
import SwiftData
import UIKit

enum AppTab: Hashable {
    case overview, stats, add, calendar, mine
}

/// 「＋」菜单目标（单一 sheet(item:) 驱动——同一视图挂多个 .sheet 只有最后一个生效）
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

/// 根框架：5 位 Tab（中间「＋」弹出来源宫格）+ App 锁遮罩（文档 §6.1 / F-12）
struct RootTabView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var appLock = AppLockManager()
    @State private var selection: AppTab = .overview
    @State private var lastSelection: AppTab = .overview

    @State private var showAddMenu = false
    @State private var showAlbumScanPrompt = false
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
                withAnimation(.spring(duration: 0.32)) { showAddMenu = true }
            } else {
                lastSelection = newValue
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .screenshotImport:
                NavigationStack {
                    ScreenshotImportView()
                }
            case .albumScan:
                NavigationStack {
                    AlbumScanView()
                }
            case .cameraCapture:
                CameraPicker { image in
                    handleCapturedForAdd(image)
                }
                .ignoresSafeArea()
            case .manualAdd(let kind, let prefill):
                AddTransactionView(mode: .create(kind, prefill))
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
            if showAddMenu {
                addMenuOverlay
            }
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

    // MARK: - 记账来源宫格（2×2，简洁无冗余文字）

    @ViewBuilder
    private var addMenuOverlay: some View {
        if showAddMenu {
            ZStack {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(duration: 0.3)) { showAddMenu = false }
                    }
                VStack(spacing: 14) {
                    HStack(spacing: 14) {
                        menuTile("截图入账", "photo.on.rectangle", "4A90D9") {
                            activeSheet = .screenshotImport
                        }
                        menuTile("拍照入账", "camera", "FF8A3D") {
                            activeSheet = .cameraCapture
                        }
                    }
                    HStack(spacing: 14) {
                        menuTile("批量扫描", "doc.text.magnifyingglass", "8E7CF8") {
                            activeSheet = .albumScan
                        }
                        menuTile("手动录入", "pencil.line", "4CAF50") {
                            activeSheet = .manualAdd(kind: .expense, prefill: nil)
                        }
                    }
                    Button {
                        withAnimation(.spring(duration: 0.3)) { showAddMenu = false }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding(18)
                .frame(maxWidth: 320)
                .glassCard(cornerRadius: 28)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
    }

    private func menuTile(_ title: String, _ icon: String, _ colorHex: String,
                          action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { showAddMenu = false }
            action()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color(hex: colorHex))
                    .frame(width: 52, height: 52)
                    .background(Color(hex: colorHex).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 拍照入账流（F-15）：拍摄 → 识别 → 预填手动表单

    private func handleCapturedForAdd(_ image: UIImage) {
        Task { @MainActor in
            activeSheet = nil
            let rows = await SmartExtractionService.extractRows(from: image)
            guard let first = rows.first, let cents = first.amountCents, cents > 0 else {
                captureHint = "未识别出支付信息，请改用「手动录入」"
                return
            }
            if rows.count > 1 {
                captureHint = "识别到 \(rows.count) 笔，已填入第一笔；其余请用「批量扫描」处理"
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
            activeSheet = .manualAdd(
                kind: first.kind ?? .expense,
                prefill: AddTransactionView.Mode.Prefill(
                    amountCents: cents,
                    date: first.date,
                    note: first.note ?? first.counterparty,
                    categoryID: nil,
                    kind: first.kind))
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
