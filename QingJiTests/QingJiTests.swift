import XCTest
import SwiftData
@testable import QingJi

/// 金额解析与格式化（文档 F-01 AC1 / §7.4）
final class MoneyTests: XCTestCase {

    func testParseBasic() {
        XCTAssertEqual(Money.cents(fromString: "12"), 1200)
        XCTAssertEqual(Money.cents(fromString: "12.5"), 1250)
        XCTAssertEqual(Money.cents(fromString: "12.56"), 1256)
        XCTAssertEqual(Money.cents(fromString: "0.01"), 1)
        XCTAssertEqual(Money.cents(fromString: ".5"), 50)
        XCTAssertEqual(Money.cents(fromString: "123456789"), 12345678900)
    }

    func testParseTruncatesExtraDecimals() {
        XCTAssertEqual(Money.cents(fromString: "1.234"), 123) // 截断到 2 位
        XCTAssertEqual(Money.cents(fromString: "1.999"), 199)
    }

    func testParseInvalid() {
        XCTAssertNil(Money.cents(fromString: ""))
        XCTAssertNil(Money.cents(fromString: "abc"))
        XCTAssertNil(Money.cents(fromString: "1.2.3"))
        XCTAssertNil(Money.cents(fromString: "-5"))
        XCTAssertNil(Money.cents(fromString: "1234567890")) // 整数位超 9 位
    }

    func testFormat() {
        XCTAssertEqual(Money.string(fromCents: 123456), "¥1,234.56")
        XCTAssertEqual(Money.string(fromCents: 5), "¥0.05")
        XCTAssertEqual(Money.string(fromCents: 0), "¥0.00")
        XCTAssertEqual(Money.string(fromCents: -1250), "-¥12.50")
        XCTAssertEqual(Money.string(fromCents: 1250, sign: true), "+¥12.50")
        XCTAssertEqual(Money.string(fromCents: -1250, sign: true), "-¥12.50")
    }

    func testRoundTrip() {
        let cents = Money.cents(fromString: "88.88")
        XCTAssertEqual(cents, 8888)
        XCTAssertEqual(Money.inputString(fromCents: cents), "88.88")
        XCTAssertEqual(Money.cents(fromYuan: Money.yuan(fromCents: 12345)), 12345)
    }

    func testYuanConversion() {
        XCTAssertEqual(Money.yuan(fromCents: 1250), Decimal(string: "12.5"))
        XCTAssertEqual(Money.cents(fromYuan: Decimal(string: "19.99") ?? 0), 1999)
    }
}

/// 日期区间（文档 F-03/F-04 区间一致性）
final class DateHelpersTests: XCTestCase {

    private var cal: Calendar { Calendar.current }

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    func testMonthRange() {
        let range = DateHelpers.range(of: .month, containing: date(2026, 9, 15))
        XCTAssertEqual(cal.component(.month, from: range.start), 9)
        XCTAssertEqual(cal.component(.day, from: range.start), 1)
        XCTAssertEqual(cal.component(.hour, from: range.start), 0)
        // end 为 9 月最后一刻：10 月 1 日 00:00 前一秒
        XCTAssertEqual(cal.component(.month, from: range.end), 9)
        XCTAssertEqual(cal.component(.day, from: range.end), 30)
    }

    func testYearRange() {
        let range = DateHelpers.range(of: .year, containing: date(2026, 3, 8))
        XCTAssertEqual(cal.component(.month, from: range.start), 1)
        XCTAssertEqual(cal.component(.day, from: range.start), 1)
        XCTAssertEqual(cal.component(.month, from: range.end), 12)
        XCTAssertEqual(cal.component(.day, from: range.end), 31)
    }

    func testWeekStartsOnMonday() {
        // 2026-09-23 是周三
        let start = DateHelpers.startOfWeek(date(2026, 9, 23))
        XCTAssertEqual(cal.component(.weekday, from: start), 2) // 周一
        XCTAssertEqual(cal.component(.day, from: start), 21)
    }

    func testShift() {
        let shifted = DateHelpers.shift(date(2026, 9, 26), by: -1, of: .month)
        XCTAssertEqual(cal.component(.month, from: shifted), 8)
    }

    func testCalendarGrid() {
        let grid = DateHelpers.calendarGrid(forMonthOf: date(2026, 9, 15))
        XCTAssertEqual(grid.count, 42)
        XCTAssertEqual(cal.component(.weekday, from: grid[0]), 2) // 首格是周一
        let first = DateHelpers.startOfMonth(date(2026, 9, 15))
        XCTAssertTrue(grid.contains(first))
    }

    func testTitle() {
        XCTAssertEqual(DateHelpers.title(of: .month, for: date(2026, 9, 26)), "2026年9月")
        XCTAssertEqual(DateHelpers.title(of: .year, for: date(2026, 9, 26)), "2026年")
    }
}

/// 统计聚合（文档 F-03 AC1/AC2）
final class StatsServiceTests: XCTestCase {

    private func makeTransaction(kind: TxKind, cents: Int64, category: Category?, date: Date = Date()) -> Transaction {
        Transaction(kind: kind, amountCents: cents, date: date, category: category)
    }

    func testTotals() {
        let food = Category(name: "餐饮", kind: .expense)
        let salary = Category(name: "工资", kind: .income)
        let txs = [
            makeTransaction(kind: .expense, cents: 3000, category: food),
            makeTransaction(kind: .expense, cents: 2000, category: food),
            makeTransaction(kind: .income, cents: 10000, category: salary),
            makeTransaction(kind: .transfer, cents: 500, category: nil),
        ]
        XCTAssertEqual(StatsService.totalCents(txs, kind: .expense), 5000)
        XCTAssertEqual(StatsService.totalCents(txs, kind: .income), 10000)
        XCTAssertEqual(StatsService.totalCents(txs, kind: .transfer), 500)
    }

    func testByCategoryPercentSumsToOne() {
        let food = Category(name: "餐饮", kind: .expense)
        let traffic = Category(name: "交通", kind: .expense)
        let txs = [
            makeTransaction(kind: .expense, cents: 7000, category: food),
            makeTransaction(kind: .expense, cents: 3000, category: traffic),
            makeTransaction(kind: .expense, cents: 500, category: nil),
        ]
        let stats = StatsService.byCategory(txs, kind: .expense)
        XCTAssertEqual(stats.count, 3)
        let percentSum = stats.reduce(0.0) { $0 + $1.percent }
        XCTAssertEqual(percentSum, 1.0, accuracy: 0.001)
        XCTAssertEqual(stats.first?.totalCents, 7000) // 降序
    }

    func testByCategoryEmpty() {
        XCTAssertTrue(StatsService.byCategory([], kind: .expense).isEmpty)
    }

    func testPieSlicesMergesTail() {
        let cats = (0..<10).map { Category(name: "分类\($0)", kind: .expense) }
        let txs = cats.enumerated().map { index, cat in
            makeTransaction(kind: .expense, cents: Int64(1000 - index * 10), category: cat)
        }
        let stats = StatsService.byCategory(txs, kind: .expense)
        let slices = StatsService.pieSlices(stats, topN: 8)
        XCTAssertEqual(slices.count, 9) // Top8 + 其他
        XCTAssertEqual(slices.last?.id, "other")
        let sum = slices.reduce(0) { $0 + $1.totalCents }
        XCTAssertEqual(sum, stats.reduce(0) { $0 + $1.totalCents })
    }

    func testByDayGroupsByNaturalDay() {
        let food = Category(name: "餐饮", kind: .expense)
        let cal = Calendar.current
        let morning = cal.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!
        let evening = cal.date(bySettingHour: 21, minute: 0, second: 0, of: Date())!
        let txs = [
            makeTransaction(kind: .expense, cents: 1000, category: food, date: morning),
            makeTransaction(kind: .expense, cents: 500, category: food, date: evening),
        ]
        let range = DateHelpers.range(of: .day, containing: Date())
        let dayTotals = StatsService.byDay(txs, kind: .expense, in: range)
        XCTAssertEqual(dayTotals.count, 1)
        XCTAssertEqual(dayTotals.first?.totalCents, 1500)
    }
}

/// 账户余额与净资产（文档 F-02 AC1）
final class LedgerServiceTests: XCTestCase {

    func testBalance() {
        let cash = Account(name: "现金", kind: .cash, initialBalanceCents: 10000)
        let bank = Account(name: "储蓄卡", kind: .bank)
        let txs = [
            Transaction(kind: .income, amountCents: 50000, account: cash),
            Transaction(kind: .expense, amountCents: 20000, account: cash),
            Transaction(kind: .transfer, amountCents: 15000, account: cash, toAccount: bank),
            Transaction(kind: .expense, amountCents: 3000, account: bank),
        ]
        XCTAssertEqual(LedgerService.balanceCents(of: cash, transactions: txs), 10000 + 50000 - 20000 - 15000)
        XCTAssertEqual(LedgerService.balanceCents(of: bank, transactions: txs), 15000 - 3000)
    }

    func testNetWorthWithCreditDebt() {
        let bank = Account(name: "储蓄卡", kind: .bank, initialBalanceCents: 20000)
        let credit = Account(name: "信用卡", kind: .credit)
        let txs = [
            Transaction(kind: .expense, amountCents: 25000, account: credit), // 刷卡 -> 欠款
        ]
        let netWorth = LedgerService.netWorthCents(accounts: [bank, credit], transactions: txs)
        XCTAssertEqual(netWorth, 20000 - 25000)
    }

    func testArchivedAccountsExcludedFromNetWorth() {
        let active = Account(name: "现金", kind: .cash, initialBalanceCents: 100)
        let archived = Account(name: "旧卡", kind: .bank, initialBalanceCents: 999, sortOrder: 1)
        archived.isArchived = true
        XCTAssertEqual(LedgerService.netWorthCents(accounts: [active, archived], transactions: []), 100)
    }
}

/// 周期引擎（文档 F-07 AC1：跨周期补齐且不重复）
final class RecurringEngineTests: XCTestCase {

    private func makeContainer() -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: Transaction.self, Account.self, Category.self,
                                   Tag.self, Attachment.self, Budget.self, RecurringRule.self,
                                   configurations: config)
    }

    private var cal: Calendar { Calendar.current }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 9))!
    }

    func testMonthlyFirstOccurrence() {
        let rule = RecurringRule(name: "房租", kind: .expense, amountCents: 300000,
                                 frequency: .monthly, dayOfMonth: 1,
                                 startDate: date(2026, 9, 20))
        let first = RecurringEngine.firstOccurrence(of: rule)
        XCTAssertEqual(first, cal.startOfDay(for: date(2026, 10, 1)))
    }

    func testMonthlyClampsToMonthEnd() {
        let rule = RecurringRule(name: "月结", kind: .expense, amountCents: 100,
                                 frequency: .monthly, dayOfMonth: 31,
                                 startDate: date(2026, 9, 1))
        let first = RecurringEngine.firstOccurrence(of: rule)
        XCTAssertEqual(first, cal.startOfDay(for: date(2026, 9, 30))) // 9 月只有 30 天
    }

    func testNextDueAfterLastPosted() {
        let rule = RecurringRule(name: "房租", kind: .expense, amountCents: 300000,
                                 frequency: .monthly, dayOfMonth: 1,
                                 startDate: date(2026, 8, 20))
        rule.lastPostedDate = cal.startOfDay(for: date(2026, 9, 1))
        let next = RecurringEngine.nextDueDate(of: rule, after: rule.lastPostedDate!)
        XCTAssertEqual(next, cal.startOfDay(for: date(2026, 10, 1)))
    }

    func testPostDueRulesCatchesUpAndIsIdempotent() throws {
        let container = makeContainer()
        let context = ModelContext(container)
        let account = Account(name: "储蓄卡", kind: .bank)
        context.insert(account)

        let rule = RecurringRule(name: "房租", kind: .expense, amountCents: 300000,
                                 frequency: .monthly, dayOfMonth: 1,
                                 startDate: date(2026, 6, 15))
        rule.account = account
        context.insert(rule)

        let upTo = date(2026, 9, 26)
        let created1 = RecurringEngine.postDueRules(rules: [rule], context: context, upTo: upTo)
        XCTAssertEqual(created1, 3) // 7-01, 8-01, 9-01
        XCTAssertEqual(rule.lastPostedDate, cal.startOfDay(for: date(2026, 9, 1)))

        // 幂等：重复调用不再产生新账
        let created2 = RecurringEngine.postDueRules(rules: [rule], context: context, upTo: upTo)
        XCTAssertEqual(created2, 0)

        // 时间推进一个月后只补 1 笔
        let created3 = RecurringEngine.postDueRules(rules: [rule], context: context, upTo: date(2026, 10, 15))
        XCTAssertEqual(created3, 1)
    }

    func testInactiveRuleSkipped() {
        let container = makeContainer()
        let context = ModelContext(container)
        let rule = RecurringRule(name: "停用", kind: .expense, amountCents: 100,
                                 frequency: .daily, startDate: date(2026, 9, 1))
        rule.isActive = false
        context.insert(rule)
        let created = RecurringEngine.postDueRules(rules: [rule], context: context, upTo: date(2026, 9, 26))
        XCTAssertEqual(created, 0)
    }

    func testEndDateRespected() {
        let rule = RecurringRule(name: "有终止", kind: .income, amountCents: 100,
                                 frequency: .daily, startDate: date(2026, 9, 1),
                                 endDate: date(2026, 9, 3))
        let next = RecurringEngine.nextDueDate(of: rule, after: date(2026, 9, 3))
        XCTAssertNil(next)
        let next2 = RecurringEngine.nextDueDate(of: rule, after: date(2026, 9, 2))
        XCTAssertEqual(next2, cal.startOfDay(for: date(2026, 9, 3)))
    }
}

/// 分类预测（文档 F-01 智能默认）
final class CategoryPredictorTests: XCTestCase {

    func testBucketBoundaries() {
        let cal = Calendar.current
        func hour(_ h: Int) -> Date {
            cal.date(bySettingHour: h, minute: 0, second: 0, of: Date())!
        }
        XCTAssertEqual(CategoryPredictor.bucket(of: hour(3)), 0)
        XCTAssertEqual(CategoryPredictor.bucket(of: hour(8)), 1)
        XCTAssertEqual(CategoryPredictor.bucket(of: hour(12)), 2)
        XCTAssertEqual(CategoryPredictor.bucket(of: hour(15)), 3)
        XCTAssertEqual(CategoryPredictor.bucket(of: hour(20)), 4)
    }

    func testRanksSameBucketHistoryFirst() {
        let breakfast = Category(name: "早餐", kind: .expense, sortOrder: 1)
        let taxi = Category(name: "打车", kind: .expense, sortOrder: 2)
        let cal = Calendar.current
        let morning = cal.date(bySettingHour: 8, minute: 30, second: 0, of: Date())!
        let evening = cal.date(bySettingHour: 20, minute: 30, second: 0, of: Date())!

        let history = [
            Transaction(kind: .expense, amountCents: 800, date: morning, category: breakfast),
            Transaction(kind: .expense, amountCents: 900, date: morning, category: breakfast),
            Transaction(kind: .expense, amountCents: 3000, date: evening, category: taxi),
        ]

        let ranked = CategoryPredictor.ranked(categories: [breakfast, taxi],
                                              transactions: history,
                                              kind: .expense,
                                              at: morning)
        XCTAssertEqual(ranked.first, breakfast)

        // 无历史时不预选
        XCTAssertNil(CategoryPredictor.topCategory(categories: [breakfast, taxi],
                                                   transactions: [],
                                                   kind: .expense,
                                                   at: morning))
    }
}

/// CSV 导出（文档 F-08 AC1）
final class CSVExporterTests: XCTestCase {

    func testExportContent() throws {
        let cash = Account(name: "现金", kind: .cash)
        let food = Category(name: "餐饮", kind: .expense)
        let tx = Transaction(kind: .expense, amountCents: 1234, account: cash, category: food, note: "午饭,加蛋")
        let url = CSVExporter.export(transactions: [tx])
        XCTAssertNotNil(url)
        let content = try String(contentsOf: url!, encoding: .utf8)
        XCTAssertTrue(content.hasPrefix("\u{FEFF}")) // BOM
        XCTAssertTrue(content.contains("日期,类型,分类,账户,转入账户,金额,备注"))
        XCTAssertTrue(content.contains("\"午饭,加蛋\"")) // 逗号转义
        XCTAssertTrue(content.contains(CSVExporter.plainYuanString(1234)))
        XCTAssertEqual(CSVExporter.plainYuanString(1234), "12.34")
    }
}
