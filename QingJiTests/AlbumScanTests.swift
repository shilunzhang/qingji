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
}
