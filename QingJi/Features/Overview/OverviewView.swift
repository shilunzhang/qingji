import SwiftUI
import SwiftData

/// 明细页（文档 F-01/F-02）：账户条 + 月汇总 + 按日分组流水
struct OverviewView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    @State private var monthAnchor = Date()
    @State private var editing: Transaction?
    @State private var showScreenshot = false

    var body: some View {
        NavigationStack {
            List {
                summarySection
                transactionSections
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemBackground))
            // v1.4.6：底部给浮动＋号让位，最后一行不被遮挡
            .contentMargins(.bottom, 88)
            .navigationTitle("明细")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showScreenshot = true
                    } label: {
                        Image(systemName: "camera.viewfinder")
                    }
                    .accessibilityLabel("截图记账")
                }
            }
            .sheet(item: $editing) { tx in
                // 修复A：编辑页取消/保存在 toolbar 中，必须包 NavigationStack
                NavigationStack {
                    AddTransactionView(mode: .edit(tx))
                }
            }
            .sheet(isPresented: $showScreenshot) {
                // v1.4.3：选择器内嵌为 sheet 内容，取消一次关闭
                QuickCaptureView(source: .album)
            }
        }
    }

    // MARK: - 数据

    private var monthTx: [Transaction] {
        LedgerService.transactions(transactions, in: DateHelpers.range(of: .month, containing: monthAnchor))
    }

    private var monthTotals: (expense: Int64, income: Int64) {
        LedgerService.totals(in: monthTx)
    }

    /// 按日分组的展示模型（元组不支持 KeyPath，需 Identifiable 结构体）
    private struct DayGroup: Identifiable {
        let date: Date
        let items: [Transaction]
        let expense: Int64
        let income: Int64
        var id: Date { date }
    }

    private var dayGroups: [DayGroup] {
        let grouped = Dictionary(grouping: monthTx) { Calendar.current.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { day in
            let items = (grouped[day] ?? []).sorted { $0.date > $1.date }
            let totals = LedgerService.totals(in: items)
            return DayGroup(date: day, items: items, expense: totals.expense, income: totals.income)
        }
    }

    // MARK: - 视图（极简杂志系：白底、大字汇总，文档 F-19；v1.4.6 汇总合一卡）

    /// 月支出/收入/结余 + 净资产/各账户 余额合并为单一卡片：
    /// 隐私开关（眼睛）在框外，开启时整框模糊（F-20）
    private var summarySection: some View {
        Section {
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 12) {
                    PeriodNavHeader(
                        title: DateHelpers.title(of: .month, for: monthAnchor),
                        onPrev: { monthAnchor = DateHelpers.shift(monthAnchor, by: -1, of: .month) },
                        onNext: { monthAnchor = DateHelpers.shift(monthAnchor, by: 1, of: .month) }
                    )
                    TotalsBar(expenseCents: monthTotals.expense, incomeCents: monthTotals.income)
                    Divider()
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 18) {
                            assetItem(
                                title: "净资产",
                                amount: netWorthCents,
                                icon: "chart.bar.doc.horizontal",
                                colorHex: "FF8A3D"
                            )
                            ForEach(accounts.filter { !$0.isArchived }) { account in
                                assetItem(
                                    title: account.name,
                                    amount: LedgerService.balanceCents(of: account, transactions: transactions),
                                    icon: account.icon,
                                    colorHex: account.colorHex
                                )
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .privacyMask() // 整框模糊（眼睛按钮在框外不模糊）

                PrivacyEyeButton()
                    .padding(.top, 4)
            }
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(uiColor: .separator).opacity(0.35), lineWidth: 1)
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
        }
    }

    private var netWorthCents: Int64 {
        LedgerService.netWorthCents(accounts: accounts, transactions: transactions)
    }

    /// 资产列：图标 + 名称 + 余额（紧凑纵向）
    private func assetItem(title: String, amount: Int64, icon: String, colorHex: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(Color(hex: colorHex))
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(Money.string(fromCents: amount))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(amount < 0 ? Theme.alert : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(minWidth: 86, alignment: .leading)
    }

    @ViewBuilder
    private var transactionSections: some View {
        if dayGroups.isEmpty {
            Section {
                EmptyStateView(icon: "tray",
                               title: "本月还没有账目",
                               hint: "点击底部「＋」记下第一笔吧")
            }
        } else {
            ForEach(dayGroups) { group in
                Section {
                    ForEach(group.items) { tx in
                        // v1.4.5：取消点按编辑（行中段空白点击无响应），改为左滑操作
                        TransactionRowView(tx: tx)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteTransaction(tx)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                Button {
                                    editing = tx
                                } label: {
                                    Label("编辑", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                    }
                } header: {
                    HStack {
                        Text(dayTitle(group.date))
                        Spacer()
                        Text(dayTotalsText(expense: group.expense, income: group.income))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func dayTitle(_ date: Date) -> String {
        let cal = Calendar.current
        let day = cal.component(.day, from: date)
        let weekdayIndex = (cal.component(.weekday, from: date) + 5) % 7
        let weekday = DateHelpers.weekdayTitles[weekdayIndex]
        return "\(cal.component(.month, from: date))月\(day)日 周\(weekday)"
    }

    /// 左滑删除：余额由流水实时计算（LedgerService.balanceCents），删除即自动回滚；
    /// 自动入账日志保留，防止自动化把用户明确删除的账目重新加回
    private func deleteTransaction(_ tx: Transaction) {
        context.delete(tx)
        try? context.save()
    }

    private func dayTotalsText(expense: Int64, income: Int64) -> String {
        var parts: [String] = []
        if expense > 0 { parts.append("支 \(Money.string(fromCents: expense))") }
        if income > 0 { parts.append("收 \(Money.string(fromCents: income))") }
        return parts.joined(separator: "  ")
    }
}
