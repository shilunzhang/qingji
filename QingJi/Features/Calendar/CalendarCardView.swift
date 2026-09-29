import SwiftUI
import SwiftData

/// 日历卡片（v1.6.0）：由明细页汇总卡左上角日历图标弹出（中等高度 sheet 卡片）。
/// 原「日历」Tab 页移除后的能力载体：月历网格（收支点标 + 当日支出短金额）
/// + 当日流水（左滑编辑/删除）。年汇总能力由「图表」页承担。
struct CalendarCardView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    @State private var monthAnchor = Date()
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var editing: Transaction?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    VStack(spacing: 8) {
                        PeriodNavHeader(
                            title: DateHelpers.title(of: .month, for: monthAnchor),
                            onPrev: { shiftMonth(-1) },
                            onNext: { shiftMonth(1) }
                        )
                        weekdayRow
                        grid
                    }
                    .card()

                    dayDetail
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("日历")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(item: $editing) { tx in
                // 编辑页取消/保存在 toolbar 中，必须包 NavigationStack
                NavigationStack {
                    AddTransactionView(mode: .edit(tx))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - 数据

    private var monthTx: [Transaction] {
        LedgerService.transactions(transactions, in: DateHelpers.range(of: .month, containing: monthAnchor))
    }

    /// 该月每日 -> 当日支出（分）
    private var dailyExpense: [Date: Int64] {
        var result: [Date: Int64] = [:]
        for tx in monthTx where tx.type == .expense {
            let day = Calendar.current.startOfDay(for: tx.date)
            result[day, default: 0] += tx.amountCents
        }
        return result
    }

    /// 该月每日 -> 当日收入（分）
    private var dailyIncome: [Date: Int64] {
        var result: [Date: Int64] = [:]
        for tx in monthTx where tx.type == .income {
            let day = Calendar.current.startOfDay(for: tx.date)
            result[day, default: 0] += tx.amountCents
        }
        return result
    }

    private var selectedDayTransactions: [Transaction] {
        transactions.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDay) }
            .sorted { $0.date > $1.date }
    }

    // MARK: - 月历

    private func shiftMonth(_ delta: Int) {
        monthAnchor = DateHelpers.shift(monthAnchor, by: delta, of: .month)
        let first = DateHelpers.startOfMonth(monthAnchor)
        let today = Calendar.current.startOfDay(for: Date())
        selectedDay = (DateHelpers.startOfMonth(today) == first) ? today : first
    }

    private var weekdayRow: some View {
        HStack {
            ForEach(DateHelpers.weekdayTitles, id: \.self) { title in
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        let grid = DateHelpers.calendarGrid(forMonthOf: monthAnchor)
        let expenseMap = dailyExpense
        let incomeMap = dailyIncome
        let inMonth = DateHelpers.startOfMonth(monthAnchor)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
            ForEach(grid, id: \.self) { day in
                let visible = DateHelpers.startOfMonth(day) == inMonth
                if visible {
                    dayCell(day: day,
                            expense: expenseMap[day] ?? 0,
                            income: incomeMap[day] ?? 0)
                } else {
                    Color.clear.frame(minHeight: 52)
                }
            }
        }
    }

    private func dayCell(day: Date, expense: Int64, income: Int64) -> some View {
        let isSelected = Calendar.current.isDate(day, inSameDayAs: selectedDay)
        let isToday = Calendar.current.isDateInToday(day)
        return Button {
            selectedDay = day
        } label: {
            VStack(spacing: 2) {
                Text("\(Calendar.current.component(.day, from: day))")
                    .font(.subheadline.weight(isToday || isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle().fill(isSelected ? Color.accentColor : Color.clear)
                    )
                    .overlay {
                        if isToday && !isSelected {
                            Circle().stroke(Color.accentColor, lineWidth: 1.5)
                        }
                    }
                HStack(spacing: 2) {
                    if income > 0 { dot(color: Theme.income) }
                    if expense > 0 { dot(color: Theme.alert) }
                }
                .frame(height: 5)
                Text(expense > 0 ? shortAmount(expense) : " ")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.alert)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.plain)
    }

    private func dot(color: Color) -> some View {
        Circle().fill(color).frame(width: 4, height: 4)
    }

    /// 日历格内的短金额：整元省略小数
    private func shortAmount(_ cents: Int64) -> String {
        cents % 100 == 0 ? "\(cents / 100)" : Money.inputString(fromCents: cents)
    }

    // MARK: - 当日流水（查账/补账）

    private var dayDetail: some View {
        VStack(alignment: .leading, spacing: 10) {
            let totals = LedgerService.totals(in: selectedDayTransactions)
            HStack {
                Text(dayTitle)
                    .font(.subheadline.weight(.medium))
                Spacer()
                if totals.expense > 0 || totals.income > 0 {
                    Text("支 \(Money.string(fromCents: totals.expense))")
                        .foregroundStyle(Theme.alert)
                    Text("收 \(Money.string(fromCents: totals.income))")
                        .foregroundStyle(Theme.income)
                }
            }
            .font(.caption)

            if selectedDayTransactions.isEmpty {
                EmptyStateView(icon: "calendar.badge.plus",
                               title: "这一天没有账目",
                               hint: "如有消费，记得补一笔哦")
            } else {
                ForEach(selectedDayTransactions) { tx in
                    // 卡片内左滑：编辑 + 删除（同明细页）
                    SwipeActionRow(
                        onEdit: { editing = tx },
                        onDelete: {
                            context.delete(tx)
                            try? context.save()
                        }
                    ) {
                        TransactionRowView(tx: tx)
                    }
                }
            }
        }
        .card()
    }

    private var dayTitle: String {
        let cal = Calendar.current
        let month = cal.component(.month, from: selectedDay)
        let day = cal.component(.day, from: selectedDay)
        let weekdayIndex = (cal.component(.weekday, from: selectedDay) + 5) % 7
        return "\(month)月\(day)日 周\(DateHelpers.weekdayTitles[weekdayIndex])"
    }
}
