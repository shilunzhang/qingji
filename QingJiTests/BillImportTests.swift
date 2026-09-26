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

    func testDedupKeys() {
        let row = ParsedBillRow(externalID: "X1",
                                date: date(2026, 9, 1, hour: 12, minute: 30),
                                amountCents: 1990,
                                kind: .expense,
                                counterparty: "a", product: "b", note: "", payMethod: "零钱")
        let key = BillDedup.fuzzyKey(of: row)
        // 同一分钟内相同金额/方向视为重复
        let sameMinute = date(2026, 9, 1, hour: 12, minute: 30).addingTimeInterval(30)
        XCTAssertEqual(BillDedup.fuzzyKey(kind: .expense, date: sameMinute, amountCents: 1990), key)
        // 不同金额不重复
        XCTAssertNotEqual(BillDedup.fuzzyKey(kind: .expense, date: row.date, amountCents: 2000), key)
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
}
