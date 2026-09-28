import XCTest
@testable import QingJi

/// 账单解析与查重（文档 F-10 AC）
final class BillParserTests: XCTestCase {

    private var cal: Calendar { Calendar.current }

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int, minute: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour, minute: minute))!
    }

    private let wechatCSV = """
    微信支付账单明细,起始时间:[2026-08-01 00:00:00] 终止时间:[2026-09-01 00:00:00]
    导出类型:[全部] 导出时间:[2026-09-20 10:00:00]
    ----------------------微信支付账单明细列表--------------------
    交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注
    "2026-09-01 12:30:00","商户消费","瑞幸咖啡","生椰拿铁","支出","¥19.90","零钱","支付成功","10001","20001","/"
    "2026-09-02 09:00:00","微信红包","张三","现金红包","收入","¥8.88","零钱","已存入零钱","10002","20002","/"
    "2026-09-03 10:00:00","转账-转账给他人","李四","转账","/","¥100.00","零钱","对方已收钱","10003","20003","/"
    "2026-09-04 11:00:00","商户消费","某某商店","商品","支出","¥50.00","招商银行(1234)","退款成功","10004","20004","/"
    """

    private let alipayCSV = """
    支付宝交易记录明细查询
    账号:demo@example.com
    ----------------------------交易记录明细列表----------------------------
    交易号,商家订单号,交易创建时间,付款时间,最近修改时间,交易来源地,类型,交易对方,商品名称,金额（元）,收/支,交易状态,服务费（元）,成功退款（元）,备注,资金状态
    2026090122001100,PO123,2026-09-01 18:20:00,2026-09-01 18:20:05,2026-09-01 18:20:05,中国,商家消费,美团,外卖订单,45.60,支出,交易成功,0.00,0.00,/,已支出
    2026090222001101,PO124,2026-09-02 10:00:00,2026-09-02 10:00:01,2026-09-02 10:00:01,中国,转账,张三,转账,200.00,收入,交易成功,0.00,0.00,/,已收入
    2026090322001102,PO125,2026-09-03 11:00:00,2026-09-03 11:00:01,2026-09-03 11:00:01,中国,退款,某某店铺,退款-订单,30.00,收入,退款成功,0.00,30.00,/,已退回
    2026090422001103,PO126,2026-09-04 12:00:00,2026-09-04 12:00:01,2026-09-04 12:00:01,中国,商家消费,京东,数码商品,1299.00,不计收支,交易成功,0.00,0.00,/,资金未变动
    """

    func testParseWeChat() throws {
        let result = try BillParser.parse(data: Data(wechatCSV.utf8))
        XCTAssertEqual(result.source, .wechat)
        XCTAssertEqual(result.rows.count, 2) // "/" 方向与退款被剔除
        XCTAssertEqual(result.skippedLines, 2)

        let first = result.rows[0]
        XCTAssertEqual(first.externalID, "10001")
        XCTAssertEqual(first.amountCents, 1990)
        XCTAssertEqual(first.kind, .expense)
        XCTAssertEqual(first.counterparty, "瑞幸咖啡")
        XCTAssertEqual(first.payMethod, "零钱")
        XCTAssertEqual(first.date, date(2026, 9, 1, hour: 12, minute: 30))

        let second = result.rows[1]
        XCTAssertEqual(second.kind, .income)
        XCTAssertEqual(second.amountCents, 888)
    }

    func testParseAlipay() throws {
        let result = try BillParser.parse(data: Data(alipayCSV.utf8))
        XCTAssertEqual(result.source, .alipay)
        XCTAssertEqual(result.rows.count, 2) // 退款 + 不计收支被剔除

        let first = result.rows[0]
        XCTAssertEqual(first.externalID, "2026090122001100")
        XCTAssertEqual(first.amountCents, 4560)
        XCTAssertEqual(first.kind, .expense)
        XCTAssertEqual(first.counterparty, "美团")
        XCTAssertEqual(first.date, date(2026, 9, 1, hour: 18, minute: 20))

        let second = result.rows[1]
        XCTAssertEqual(second.kind, .income)
        XCTAssertEqual(second.amountCents, 20000)
    }

    func testUnrecognizedFormat() {
        XCTAssertThrowsError(try BillParser.parse(data: Data("name,amount\nfoo,1".utf8))) { error in
            XCTAssertTrue(error is BillParseError)
        }
    }

    func testDecodeGB18030Fallback() {
        // "支付宝" 的 GB18030 编码字节
        let gbBytes: [UInt8] = [0xD6, 0xA7, 0xB8, 0xB6, 0xB1, 0xA6] // 支付宝
        let decoded = BillParser.decode(Data(gbBytes))
        XCTAssertEqual(decoded, "支付宝")
    }

    func testCSVLineWithQuotes() {
        let cells = BillParser.parseCSVLine(#""a,b","plain","say ""hi"""#)
        XCTAssertEqual(cells.count, 3)
        XCTAssertEqual(cells[0], "a,b")
        XCTAssertEqual(cells[1], "plain")
    }

    func testFuzzyKeyStable() {
        let base = date(2026, 9, 1, hour: 12, minute: 30)
        let key = BillDedup.fuzzyKey(kind: .expense, date: base, amountCents: 1990)
        let sameMinute = base.addingTimeInterval(30)
        XCTAssertEqual(BillDedup.fuzzyKey(kind: .expense, date: sameMinute, amountCents: 1990), key)
        XCTAssertNotEqual(BillDedup.fuzzyKey(kind: .expense, date: base, amountCents: 2000), key)
    }
}

/// 支付文本解析（文档 F-09 AC：主流截图识别金额）
final class PaymentTextParserTests: XCTestCase {

    func testAlipayStyleScreenshot() {
        let text = """
        支付成功
        付款金额 ¥1,234.56
        收款方：星巴克咖啡
        交易时间 2026-09-26 12:30:05
        支付方式 支付宝余额
        """
        let parsed = PaymentTextParser.parse(text)
        XCTAssertEqual(parsed.amountCents, 123456)
        XCTAssertEqual(parsed.counterparty, "星巴克咖啡")
        XCTAssertNotNil(parsed.date)
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: parsed.date!)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 9)
        XCTAssertEqual(comps.day, 26)
        XCTAssertEqual(comps.hour, 12)
        XCTAssertEqual(comps.minute, 30)
        XCTAssertEqual(comps.second, 5)
    }

    func testWeChatStyleScreenshot() {
        let text = """
        微信支付
        当前状态 支付成功
        付款金额 ￥88.00
        收款方 沃尔玛
        """
        let parsed = PaymentTextParser.parse(text)
        XCTAssertEqual(parsed.amountCents, 8800)
        XCTAssertEqual(parsed.counterparty, "沃尔玛")
    }

    func testPrefersLabeledOverDiscount() {
        let text = """
        支付成功
        优惠 -¥5.00
        实付 ¥95.00
        """
        let parsed = PaymentTextParser.parse(text)
        XCTAssertEqual(parsed.amountCents, 9500)
    }

    func testFallbackToMaxCurrencyAmount() {
        let text = """
        订单详情
        商品总价 ￥120.00
        运费 ￥8.00
        合计 ￥128.00
        """
        let parsed = PaymentTextParser.parse(text)
        XCTAssertEqual(parsed.amountCents, 12800)
    }

    func testNoAmountFound() {
        let parsed = PaymentTextParser.parse("设置\n关于\n版本 1.0")
        XCTAssertNil(parsed.amountCents)
    }

    func testChineseDate() {
        let parsed = PaymentTextParser.parse("交易时间：2026年9月26日 08:05")
        let comps = Calendar.current.dateComponents([.hour, .minute], from: parsed.date ?? Date())
        XCTAssertEqual(comps.hour, 8)
        XCTAssertEqual(comps.minute, 5)
    }

    // MARK: - v1.4.4 相对时间解析（昨天 21:30 / 20:30）

    /// 固定"现在"：2026-09-26 10:00（周六）
    private var fixedNow: Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 9; comps.day = 26; comps.hour = 10; comps.minute = 0
        return Calendar.current.date(from: comps)!
    }

    private func comps(of date: Date?) -> DateComponents {
        Calendar.current.dateComponents([.month, .day, .hour, .minute], from: date ?? Date())
    }

    func testRelativeDayWordLabeledTime() {
        // 交易时间：昨天 21:30 → 2026-09-25 21:30
        let parsed = PaymentTextParser.parse("支付成功\n付款金额 ¥35.00\n交易时间 昨天 21:30",
                                             now: fixedNow)
        let c = comps(of: parsed.date)
        XCTAssertEqual([c.month, c.day, c.hour, c.minute], [9, 25, 21, 30])
    }

    func testBareTimeTodayPast() {
        // 交易时间：08:30（今天 10:00 之前）→ 今天 08:30
        let parsed = PaymentTextParser.parse("交易时间 08:30", now: fixedNow)
        let c = comps(of: parsed.date)
        XCTAssertEqual([c.day, c.hour, c.minute], [26, 8, 30])
    }

    func testBareTimeFutureMeansYesterday() {
        // 交易时间：20:30（晚于当前 10:00，今天不可能出现未来时刻）→ 昨天 20:30
        let parsed = PaymentTextParser.parse("交易时间 20:30", now: fixedNow)
        let c = comps(of: parsed.date)
        XCTAssertEqual([c.day, c.hour, c.minute], [25, 20, 30])
    }

    func testFullDateTakesPriorityOverRelative() {
        // 全日期优先于相对时间
        let text = "交易时间 2026-09-20 12:00\n创建时间 昨天 21:30"
        let parsed = PaymentTextParser.parse(text, now: fixedNow)
        let c = comps(of: parsed.date)
        XCTAssertEqual([c.day, c.hour], [20, 12])
    }

    func testBillListRelativeHeaders() {
        // 账单列表：相对分组头 + 独立时间行
        let text = """
        昨天 21:35
        麦当劳 -¥35.00
        今天
        地铁 +¥6.00
        """
        let rows = PaymentTextParser.parseAll(text, now: fixedNow)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].counterparty, "麦当劳")
        let c0 = comps(of: rows[0].date)
        XCTAssertEqual([c0.day, c0.hour, c0.minute], [25, 21, 35])
        XCTAssertEqual(rows[0].kind, .expense)
        // 「今天」分组头 → 今天（12:00 粒度）
        XCTAssertEqual(comps(of: rows[1].date).day, 26)
        XCTAssertEqual(rows[1].kind, .income)
    }

    func testInlineDayWordTimeStrippedFromName() {
        // 行内相对时间：从商户名中剥离（列表页多行场景）
        let rows = PaymentTextParser.parseAll("""
        昨天 21:35 麦当劳 -¥35.00
        今天 08:10 地铁 +¥6.00
        """, now: fixedNow)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].counterparty, "麦当劳")
        XCTAssertEqual(rows[0].kind, .expense)
        let c0 = comps(of: rows[0].date)
        XCTAssertEqual([c0.day, c0.hour, c0.minute], [25, 21, 35])
        XCTAssertEqual(rows[1].counterparty, "地铁")
        XCTAssertEqual(rows[1].kind, .income)
        let c1 = comps(of: rows[1].date)
        XCTAssertEqual([c1.day, c1.hour, c1.minute], [26, 8, 10])
    }

    func testSingleSignedRowBorrowsMerchantFromRowCleanup() {
        // 单行列表行截图：parse() 无标签收款方时，借用符号行清洗出的商户名与方向
        let rows = PaymentTextParser.parseAll("昨天 21:35 麦当劳 -¥35.00", now: fixedNow)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].amountCents, 3500)
        XCTAssertEqual(rows[0].counterparty, "麦当劳")
        XCTAssertEqual(rows[0].kind, .expense)
        let c = comps(of: rows[0].date)
        XCTAssertEqual([c.day, c.hour, c.minute], [25, 21, 35])
    }

    func testLLMRelativeTimeFallback() {
        // LLM 输出相对时间 → SmartExtractionService.parseTime 兜底
        let yesterday = SmartExtractionService.parseTime("昨天 21:30", fallback: fixedNow)
        let c1 = comps(of: yesterday)
        XCTAssertEqual([c1.day, c1.hour, c1.minute], [25, 21, 30])

        let today = SmartExtractionService.parseTime("20:30", fallback: fixedNow)
        let c2 = comps(of: today)
        XCTAssertEqual([c2.day, c2.hour, c2.minute], [25, 20, 30])

        // 标准格式不受影响
        let standard = SmartExtractionService.parseTime("2026-09-01 09:05", fallback: fixedNow)
        let c3 = comps(of: standard)
        XCTAssertEqual([c3.day, c3.hour, c3.minute], [1, 9, 5])

        // 完全无法解析 → 回退 fallback
        XCTAssertEqual(SmartExtractionService.parseTime("不认识的时间", fallback: fixedNow), fixedNow)
    }
}
