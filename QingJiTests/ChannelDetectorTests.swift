import XCTest
@testable import QingJi

/// 渠道识别（文档 v1.4）
final class ChannelDetectorTests: XCTestCase {

    func testAlipay() {
        XCTAssertEqual(ChannelDetector.detect("支付宝 支付成功 付款金额¥45.60"), .alipay)
        XCTAssertEqual(ChannelDetector.detect("余额宝收益"), .alipay)
        XCTAssertEqual(ChannelDetector.detect("花呗还款"), .alipay)
    }

    func testWechat() {
        XCTAssertEqual(ChannelDetector.detect("微信支付凭证"), .wechat)
        XCTAssertEqual(ChannelDetector.detect("零钱通"), .wechat)
    }

    func testBank() {
        XCTAssertEqual(ChannelDetector.detect("招商银行 信用卡 交易提醒"), .bank)
        XCTAssertEqual(ChannelDetector.detect("储蓄卡消费"), .bank)
    }

    func testUnionPay() {
        XCTAssertEqual(ChannelDetector.detect("云闪付 支付成功"), .unionpay)
    }

    func testUnknown() {
        XCTAssertEqual(ChannelDetector.detect("某商店小票 无渠道信息"), .unknown)
        XCTAssertEqual(ChannelDetector.detect(""), .unknown)
    }

    func testPriorityAlipayOverBank() {
        // 同时出现时按优先级：支付宝特征最独特
        XCTAssertEqual(ChannelDetector.detect("支付宝 储蓄卡付款"), .alipay)
    }

    func testAccountKindMapping() {
        XCTAssertEqual(TxChannel.alipay.accountKind, .alipay)
        XCTAssertEqual(TxChannel.wechat.accountKind, .wechat)
        XCTAssertEqual(TxChannel.bank.accountKind, .bank)
        XCTAssertEqual(TxChannel.unionpay.accountKind, .bank)
        XCTAssertNil(TxChannel.unknown.accountKind)
    }

    func testTransactionChannelInfo() {
        let tx = Transaction(kind: .expense, amountCents: 100, channel: .wechat)
        XCTAssertEqual(tx.channelInfo, .wechat)

        let noChannel = Transaction(kind: .expense, amountCents: 100)
        XCTAssertNil(noChannel.channelInfo)
    }
}
