import SwiftUI
import SwiftData

/// 明细页（文档 F-01/F-02）：账户条 + 月汇总 + 按日分组流水
struct OverviewView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    @State private var monthAnchor = Date()
    @State private var editing: Transaction?
    /// v1.4.8：下拉扫描后弹出相册批量确认页
    @State private var showAlbumScan = false
    /// v1.6.0：汇总卡左上角日历图标弹出的日历卡片
    @State private var showCalendar = false

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
            // v1.4.7：去除页面大标题（底部 Tab 已标明页面），导航栏整体隐藏；
            // 原右上角相机入口与 FAB「截图入账」功能重复，一并移除
            .toolbar(.hidden, for: .navigationBar)
            // v1.4.8：明细页下拉 → 直接批量扫描相册新截图（替代 FAB 批量扫描入口）：
            // 首次下拉请求照片权限；扫到新草稿才弹相册扫描确认页，无新内容则静默收起
            .refreshable {
                if !PhotoScanService.isAuthorized {
                    _ = await PhotoScanService.requestAccess()
                }
                await AlbumScanModel.shared.scan()
                if !AlbumScanModel.shared.drafts.isEmpty {
                    showAlbumScan = true
                }
            }
            .sheet(isPresented: $showAlbumScan) {
                NavigationStack { AlbumScanView() }
            }
            // v1.6.0：日历卡片（中等高度 sheet，月历网格 + 当日流水）
            .sheet(isPresented: $showCalendar) {
                CalendarCardView()
            }
            .sheet(item: $editing) { tx in
                // 修复A：编辑页取消/保存在 toolbar 中，必须包 NavigationStack
                NavigationStack {
                    AddTransactionView(mode: .edit(tx))
                }
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
    /// v1.5.5 改用系统 listRowBackground 画分组卡背景——与下方账目分区同一布局机制，
    /// 像素级同宽对齐（此前手绘背景靠猜内边距，始终有偏差且暗色模式不一致）；
    /// 眼睛图标以覆盖层浮在框右上角（月份行右侧空区），不挤占内容列
    private var summarySection: some View {
        Section {
            ZStack(alignment: .topTrailing) {
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
                .privacyMask() // 整框模糊（眼睛覆盖其上，不受模糊影响）

                // 覆盖层：浮在月份行右侧空区，不占布局宽度，主信息恢复整宽居中
                PrivacyEyeButton()
            }
            // v1.6.0：日期左侧日历图标（与右侧眼睛对称），点击弹出日历卡片
            .overlay(alignment: .topLeading) {
                Button {
                    showCalendar = true
                } label: {
                    Image(systemName: "calendar")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("日历")
            }
            .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
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
