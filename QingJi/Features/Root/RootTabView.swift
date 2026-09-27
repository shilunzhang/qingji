import SwiftUI
import SwiftData
import UIKit

enum AppTab: Hashable {
    case overview, stats, add, calendar, mine
}

/// 根框架：5 位 Tab（中间「＋」弹出来源菜单）+ App 锁遮罩（文档 §6.1 / F-12）
struct RootTabView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var appLock = AppLockManager()
    @State private var selection: AppTab = .overview
    @State private var lastSelection: AppTab = .overview

    @State private var showAddMenu = false
    @State private var showManualAdd = false
    @State private var showScreenshotImport = false
    @State private var showAlbumScan = false
    @State private var showCameraCapture = false
    @State private var cameraPrefillKind: TxKind = .expense
    @State private var cameraPrefill: AddTransactionView.Mode.Prefill?
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
                showAddMenu = true
            } else {
                lastSelection = newValue
            }
        }
        .sheet(isPresented: $showManualAdd) {
            AddTransactionView(mode: .create(cameraPrefillKind, cameraPrefill))
        }
        .sheet(isPresented: $showScreenshotImport) {
            NavigationStack {
                ScreenshotImportView()
            }
        }
        .sheet(isPresented: $showAlbumScan) {
            NavigationStack {
                AlbumScanView()
            }
        }
        .sheet(isPresented: $showCameraCapture) {
            CameraPicker { image in
                handleCapturedForAdd(image)
            }
            .ignoresSafeArea()
        }
        .alert("识别提示", isPresented: Binding(
            get: { captureHint != nil },
            set: { if !$0 { captureHint = nil } }
        )) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(captureHint ?? "")
        }
        .overlay { addMenuOverlay }
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
                    showAlbumScan = true
                }
            }
        }
    }

    // MARK: - 记账来源菜单（文档 F-12：「＋」浮出四项）

    @ViewBuilder
    private var addMenuOverlay: some View {
        if showAddMenu {
            ZStack {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.15)) { showAddMenu = false }
                    }
                VStack(spacing: 12) {
                    Text("选择记账方式")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    menuItem(title: "截图入账",
                             subtitle: "从相册选择支付截图识别",
                             icon: "photo.on.rectangle",
                             colorHex: "4A90D9") {
                        showScreenshotImport = true
                    }
                    menuItem(title: "拍照入账",
                             subtitle: "拍摄支付页面自动识别",
                             icon: "camera",
                             colorHex: "FF8A3D") {
                        showCameraCapture = true
                    }
                    menuItem(title: "批量扫描截图入账",
                             subtitle: "扫描相册中最近的截图",
                             icon: "doc.text.magnifyingglass",
                             colorHex: "8E7CF8") {
                        showAlbumScan = true
                    }
                    menuItem(title: "手动录入账目",
                             subtitle: "传统表单填写",
                             icon: "pencil.line",
                             colorHex: "4CAF50") {
                        cameraPrefill = nil
                        cameraPrefillKind = .expense
                        showManualAdd = true
                    }

                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { showAddMenu = false }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.2), radius: 20, y: 4)
                .padding(.horizontal, 40)
                .padding(.bottom, 100)
            }
            .transition(.opacity)
        }
    }

    private func menuItem(title: String, subtitle: String, icon: String, colorHex: String,
                          action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { showAddMenu = false }
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color(hex: colorHex))
                    .frame(width: 36, height: 36)
                    .background(Color(hex: colorHex).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color(uiColor: .tertiarySystemFill).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 拍照入账流（F-15）：拍摄 → 识别 → 预填手动表单

    private func handleCapturedForAdd(_ image: UIImage) {
        Task {
            let rows = await SmartExtractionService.extractRows(from: image)
            await MainActor.run {
                guard let first = rows.first, let cents = first.amountCents, cents > 0 else {
                    captureHint = "未识别出支付信息，请改用「手动录入账目」"
                    return
                }
                cameraPrefillKind = first.kind ?? .expense
                cameraPrefill = AddTransactionView.Mode.Prefill(
                    amountCents: cents,
                    date: first.date,
                    note: first.note ?? first.counterparty,
                    categoryID: nil,
                    kind: first.kind)
                if rows.count > 1 {
                    captureHint = "识别到 \(rows.count) 笔，已填入第一笔；其余请用「批量扫描截图入账」处理"
                }
                // 等相机弹窗完全收起再呈现表单
                Task {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    showManualAdd = true
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
