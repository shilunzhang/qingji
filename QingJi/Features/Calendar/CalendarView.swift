import SwiftUI
import SwiftData

/// 记账日历（文档 F-04）：月历标记 + 当日流水（查账/补账/改账）+ 年汇总
struct CalendarView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    @State private var monthAnchor = Date()
    @State private var showYear = false
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var editing: Transaction?

    var body: some View {
        NavigationStack {
            Group {
                if showYear {
                    yearSummary
                } else {
                    monthCalendar
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("日历")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(showYear ? "月" : "年") {
                        showYear.toggle()
                    }
                    .font(.subheadline.weight(.medium))
                }
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

    private var monthCalendar: some View {
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
    }

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
                    Button {
                        editing = tx
                    } label: {
                        TransactionRowView(tx: tx)
                    }
                    .buttonStyle(.plain)
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

    // MARK: - 年汇总

    private var yearSummary: some View {
        List {
            Section {
                PeriodNavHeader(
                    title: DateHelpers.title(of: .year, for: monthAnchor),
                    onPrev: { monthAnchor = DateHelpers.shift(monthAnchor, by: -1, of: .year) },
                    onNext: { monthAnchor = DateHelpers.shift(monthAnchor, by: 1, of: .year) }
                )
                .padding(.vertical, 4)
            }
            ForEach(1...12, id: \.self) { month in
                let row = monthTotals(year: yearValue, month: month)
                Section {
                    Button {
                        var comps = DateComponents()
                        comps.year = yearValue
                        comps.month = month
                        comps.day = 1
                        if let date = Calendar.current.date(from: comps) {
                            monthAnchor = date
                            selectedDay = date
                            showYear = false
                        }
                    } label: {
                        HStack {
                            Text("\(month)月")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("支 \(Money.string(fromCents: row.expense))")
                                    .foregroundStyle(Theme.alert)
                                Text("收 \(Money.string(fromCents: row.income))")
                                    .foregroundStyle(Theme.income)
                            }
                            .font(.caption)
                            .monospacedDigit()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var yearValue: Int {
        Calendar.current.component(.year, from: monthAnchor)
    }

    private func monthTotals(year: Int, month: Int) -> (expense: Int64, income: Int64) {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        guard let date = Calendar.current.date(from: comps) else { return (0, 0) }
        let range = DateHelpers.range(of: .month, containing: date)
        let monthTransactions = LedgerService.transactions(transactions, in: range)
        return LedgerService.totals(in: monthTransactions)
    }
}
