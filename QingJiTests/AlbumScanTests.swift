import XCTest
@testable import QingJi

/// F-13 相册扫描：支付页判定 + 已处理登记 + 增量时间
final class AlbumScanTests: XCTestCase {

    // MARK: - 支付页特征判定

    func testLooksLikePaymentPagePositive() {
        let alipay = """
        支付成功
        付款金额 ¥45.60
        收款方：美团
        """
        XCTAssertTrue(PaymentTextParser.looksLikePaymentPage(alipay))

        let income = """
        收款到账通知
        收款金额 ¥1,000.00
        付款方：张三
        """
        XCTAssertTrue(PaymentTextParser.looksLikePaymentPage(income))
    }

    func testLooksLikePaymentPageKeywordWithoutAmount() {
        XCTAssertFalse(PaymentTextParser.looksLikePaymentPage("支付成功的页面标题，但这里没有可解析的数字"))
    }

    func testLooksLikePaymentPageAmountWithoutKeyword() {
        // 聊天/文章里出现零散数字，无支付关键词 → 非支付页
        XCTAssertFalse(PaymentTextParser.looksLikePaymentPage("今天花了 45.6 元买奶茶，好贵"))
        XCTAssertFalse(PaymentTextParser.looksLikePaymentPage("这个商品卖 19999"))
    }

    func testLooksLikePaymentPageEmpty() {
        XCTAssertFalse(PaymentTextParser.looksLikePaymentPage(""))
    }

    // MARK: - 已处理登记

    func testProcessedIDsAndCapacityCap() {
        let suiteName = "qingji.album.tests"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)

        XCTAssertTrue(AlbumScanStore.processedIDs(defaults: suite).isEmpty)

        for index in 0..<505 {
            AlbumScanStore.markProcessed("asset-\(index)", defaults: suite)
        }

        let ids = AlbumScanStore.processedIDs(defaults: suite)
        XCTAssertEqual(ids.count, 500)
        XCTAssertTrue(ids.contains("asset-504")) // 最新保留
        XCTAssertFalse(ids.contains("asset-0"))  // 最老被裁剪

        // 重复登记幂等
        AlbumScanStore.markProcessed("asset-504", defaults: suite)
        XCTAssertEqual(AlbumScanStore.processedIDs(defaults: suite).count, 500)
    }

    func testLastScanDateRoundTrip() {
        let suiteName = "qingji.album.scandate.tests"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)

        XCTAssertNil(AlbumScanStore.lastScanDate(defaults: suite))

        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        AlbumScanStore.setLastScanDate(stamp, defaults: suite)
        XCTAssertEqual(AlbumScanStore.lastScanDate(defaults: suite), stamp)

        // 置空
        AlbumScanStore.setLastScanDate(nil, defaults: suite)
        XCTAssertNil(AlbumScanStore.lastScanDate(defaults: suite))
    }

    // MARK: - 多笔解析（账单列表页一行一笔）

    func testParseAllBillList() {
        let text = """
        微信记账本
        9月26日
        瑞幸咖啡 -¥19.90
        美团外卖 -¥45.60
        9月25日
        工资到账 +¥3000.00
        """
        let rows = PaymentTextParser.parseAll(text)
        XCTAssertEqual(rows.count, 3)

        XCTAssertEqual(rows[0].amountCents, 1990)
        XCTAssertEqual(rows[0].kind, .expense)
        XCTAssertEqual(rows[0].counterparty, "瑞幸咖啡")

        XCTAssertEqual(rows[1].amountCents, 4560)
        XCTAssertEqual(rows[1].counterparty, "美团外卖")

        XCTAssertEqual(rows[2].kind, .income)
        XCTAssertEqual(rows[2].amountCents, 300000)
        XCTAssertEqual(rows[2].counterparty, "工资到账")

        // 日期分组头生效：前两笔 9/26，第三笔 9/25
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.day, from: rows[0].date ?? .distantFuture), 26)
        XCTAssertEqual(cal.component(.day, from: rows[2].date ?? .distantFuture), 25)
    }

    func testParseAllSingleDetailFallsBack() {
        let detail = """
        支付成功
        付款金额 ¥45.60
        收款方：星巴克
        """
        let rows = PaymentTextParser.parseAll(detail)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].amountCents, 4560)
    }

    func testParseAllNonPaymentEmpty() {
        XCTAssertTrue(PaymentTextParser.parseAll("随便聊聊天，今天天气不错").isEmpty)
    }

    func testExtractSignedRowsSkipsSummaryLines() {
        let text = """
        合计 -¥65.50
        余额 ¥100.00
        瑞幸咖啡 -¥19.90
        """
        let rows = PaymentTextParser.extractSignedRows(text)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].counterparty, "瑞幸咖啡")
    }
}
