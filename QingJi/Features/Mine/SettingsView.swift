import SwiftUI
import SwiftData

/// 我的页（文档 F-08）：入口聚合 + 净资产 + App 锁 + CSV 导出
struct SettingsView: View {
    @EnvironmentObject private var appLock: AppLockManager
    @Environment(\.modelContext) private var context

    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("净资产")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(Money.string(fromCents: netWorth))
                                .font(.title.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(netWorth < 0 ? Theme.alert : .primary)
                        }
                        Spacer()
                        Text("共 \(activeAccounts.count) 个账户 · \(transactions.count) 笔账目")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }

                Section("记账") {
                    NavigationLink("预算管理") { BudgetView() }
                    NavigationLink("周期记账") { RecurringListView() }
                }

                Section("管理") {
                    NavigationLink("账户管理") { AccountManageView() }
                    NavigationLink("分类管理") { CategoryManageView() }
                }

                Section("数据") {
                    NavigationLink("账单导入") { ImportView() }
                    NavigationLink("截图记账") { ScreenshotImportView() }
                    if let exportURL {
                        ShareLink(item: exportURL) {
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
            .navigationTitle("我的")
            .onAppear { appLock.refreshAvailability() }
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
