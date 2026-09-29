import SwiftUI
import SwiftData

/// 我的页（文档 F-08）：入口聚合 + 净资产 + App 锁 + CSV 导出。
/// v1.6.3：由明细页右上角头像图标以 fullScreenCover **整页**呈现（非卡片）；
/// 全屏 cover 无下滑关闭，故本页保留导航栏并自带「完成」关闭按钮
struct SettingsView: View {
    @EnvironmentObject private var appLock: AppLockManager
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    @State private var exportURL: URL?
    @State private var sensitivity: DuplicateSensitivity = DuplicateGuard.sensitivity
    @State private var autoDelete = AlbumScanSettings.autoDeleteProcessedScreenshots
    @State private var showAlbumScan = false
    @State private var showSetupGuide = false
    @State private var showAutoPostLog = false
    @State private var showDiagnostics = false
    @State private var showCloudAI = false

    private var sensitivityBinding: Binding<DuplicateSensitivity> {
        Binding(
            get: { sensitivity },
            set: { newValue in
                sensitivity = newValue
                DuplicateGuard.sensitivity = newValue
            }
        )
    }

    private var autoSaveBinding: Binding<Bool> {
        Binding(
            get: { CaptureSettings.autoSave },
            set: { CaptureSettings.autoSave = $0 }
        )
    }

    private var autoDeleteBinding: Binding<Bool> {
        Binding(
            get: { autoDelete },
            set: { newValue in
                autoDelete = newValue
                AlbumScanSettings.autoDeleteProcessedScreenshots = newValue
            }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("净资产")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            // v1.4.6：隐私开关开启时模糊数字（与明细页汇总卡全局同步）
                            Text(Money.string(fromCents: netWorth))
                                .font(.title.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(netWorth < 0 ? Theme.alert : .primary)
                                .privacyMask()
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            PrivacyEyeButton()
                            Text("共 \(activeAccounts.count) 个账户 · \(transactions.count) 笔账目")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("记账") {
                    NavigationLink("预算管理") { BudgetView() }
                    NavigationLink("周期记账") { RecurringListView() }
                }

                Section {
                    Toggle("静默自动入账", isOn: autoSaveBinding)
                    Toggle("入账后删除已处理截图", isOn: autoDeleteBinding)
                    Button("云端智能抽取（自带 Key）") { showCloudAI = true }
                        .foregroundStyle(.primary)
                    Button("快捷指令配置指引") { showSetupGuide = true }
                        .foregroundStyle(.primary)
                    Button("相册扫描记账") { showAlbumScan = true }
                        .foregroundStyle(.primary)
                    Button("自动入账记录") { showAutoPostLog = true }
                        .foregroundStyle(.primary)
                    Button("诊断信息") { showDiagnostics = true }
                        .foregroundStyle(.primary)
                    Picker("重复账目处理", selection: sensitivityBinding) {
                        ForEach(DuplicateSensitivity.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                } header: {
                    Text("自动记账")
                } footer: {
                    Text("识别增强优先级：端侧大模型（Apple Intelligence）→ 云端（自带 Key，默认关闭）→ 规则。开启静默自动入账后，识别到支付将直接入账（仍受防重保护）。删除截图仅针对已入账的，删除前系统会弹确认框")
                }

                Section("管理") {
                    NavigationLink("账户管理") { AccountManageView() }
                    NavigationLink("分类管理") { CategoryManageView() }
                }

                Section("数据") {
                    NavigationLink("账单导入") { ImportView() }
                    NavigationLink("截图入账") { QuickCaptureView(source: .album) }
                    if let url = exportURL {
                        ShareLink(item: url) {
                            Label("分享账单 CSV", systemImage: "square.and.arrow.up")
                        }
                        Button("重新导出", systemImage: "arrow.clockwise") {
                            exportURL = CSVExporter.export(transactions: transactions)
                        }
                    } else {
                        Button {
                            exportURL = CSVExporter.export(transactions: transactions)
                        } label: {
                            Label("导出账单 CSV", systemImage: "square.and.arrow.up")
                        }
                    }
                }

                Section {
                    Toggle(isOn: appLockBinding) {
                        Label("App 锁", systemImage: "faceid")
                    }
                    .disabled(!appLock.biometryAvailable)
                } footer: {
                    if appLock.biometryAvailable {
                        Text("开启后离开 App 即锁定，返回需 Face ID 或密码解锁")
                    } else {
                        Text("本机未设置密码/Face ID，无法启用 App 锁")
                    }
                }

                Section {
                    NavigationLink("关于轻记") { AboutView() }
                } footer: {
                    Text("数据存储在本机与你的 iCloud，开发者无法读取")
                }
            }
            // v1.6.3：整页呈现需自带出口——小标题 + 「完成」关闭（推入的二级页面标题保留）
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear { appLock.refreshAvailability() }
            .sheet(isPresented: $showSetupGuide) {
                NavigationStack { SetupGuideView() }
            }
            .sheet(isPresented: $showAlbumScan) {
                NavigationStack { AlbumScanView() }
            }
            .sheet(isPresented: $showAutoPostLog) {
                NavigationStack { AutoPostLogView() }
            }
            .sheet(isPresented: $showDiagnostics) {
                NavigationStack { DiagnosticsView() }
            }
            .sheet(isPresented: $showCloudAI) {
                NavigationStack { CloudAISettingsView() }
            }
        }
    }

    private var activeAccounts: [Account] { accounts.filter { !$0.isArchived } }

    private var netWorth: Int64 {
        LedgerService.netWorthCents(accounts: accounts, transactions: transactions)
    }

    private var appLockBinding: Binding<Bool> {
        Binding(
            get: { appLock.isEnabled },
            set: { appLock.isEnabled = $0 }
        )
    }
}

/// 关于页
struct AboutView: View {
    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "banknote.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Color.accentColor)
                    Text("轻记")
                        .font(.title2.weight(.semibold))
                    Text("轻松省心，记一笔就好")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            Section("版本") {
                LabeledContent("版本号", value: versionString)
                LabeledContent("最低支持", value: "iOS 18.0")
            }
            Section {
                LabeledContent("同步方式", value: "iCloud / 本机")
                LabeledContent("金额精度", value: "分（整数存储，无浮点误差）")
            }
        }
        .navigationTitle("关于")
    }

    private var versionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}
