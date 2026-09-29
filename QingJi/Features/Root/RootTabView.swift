import SwiftUI
import SwiftData
import UIKit

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

/// 根框架（v1.6.3）：单明细界面——Tab 栏移除，整个 App 只有明细页；
/// 「我的」改为顶部右上角头像图标（纯符号，与汇总卡眼睛同形、字号略大），
/// 点击以**整页 fullScreenCover**呈现（非卡片）；右下角浮动记账按钮保留
struct RootTabView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var appLock = AppLockManager()
    @State private var activeSheet: AddSheet?
    @State private var captureHint: String?
    @State private var showMine = false

    var body: some View {
        OverviewView()
            // v1.6.3：顶部安全区下留一条 40pt 空白条放「我的」图标——无导航栏，
            // 空白条把汇总卡压在图标之下，静止时与卡内眼睛错开
            .safeAreaInset(edge: .top, spacing: 0) { mineEntryBar }
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
        // v1.6.3：我的页整页呈现；fullScreenCover 无下滑关闭，关闭按钮在页内
        .fullScreenCover(isPresented: $showMine) {
            SettingsView()
                .environmentObject(appLock)
        }
        // 模态由独立图层承载，锁屏遮罩盖不住——锁定即收起我的页，
        // 回前台先看到解锁遮罩（此前 Tab 结构无此问题）
        .onChange(of: appLock.isLocked) { _, locked in
            if locked { showMine = false }
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

    // MARK: - 「我的」入口（v1.6.3）

    /// 顶部窄条：仅一个头像图标贴右上角。沿用眼睛图标的纯符号形式
    /// （secondary 无底、无边框、无玻璃），仅字号/命中区 32→38pt 略放大；
    /// 条带本身留空不铺底色——卡住下拉刷新转圈（明细页下拉=扫描相册）会画在
    /// 顶部安全区里，铺不透明底色会把转圈盖住；空白条同时把汇总卡压在图标之下，
    /// 静止时图标与卡内眼睛不重叠
    private var mineEntryBar: some View {
        HStack(spacing: 0) {
            Spacer()
            Button {
                showMine = true
            } label: {
                Image(systemName: "person.crop.circle")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 38, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("我的")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 2)
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
