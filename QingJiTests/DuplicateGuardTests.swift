import XCTest
import SwiftData
@testable import QingJi

private typealias Category = QingJi.Category

/// F-14 统一防重闸门：窗口匹配 / 决策 / 指纹 / 三层导入查重
final class DuplicateGuardTests: XCTestCase {

    private var cal: Calendar { Calendar.current }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ hh: Int = 12, _ mm: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: hh, minute: mm))!
    }

    private func tx(_ kind: TxKind,
                    _ cents: Int64,
                    _ date: Date,
                    source: TxSource = .manual) -> Transaction {
        let t = Transaction(kind: kind, amountCents: cents, date: date)
        t.source = source.rawValue
        return t
    }

    // MARK: - 窗口匹配

    func testWindowHit() {
        let base = date(2026, 9, 26, 14, 30)
        let history = [tx(.expense, 4560, base)]
        let match = DuplicateGuard.findDuplicate(of: .expense,
                                                 amountCents: 4560,
                                                 date: base.addingTimeInterval(300),
                                                 in: history)
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.minutesApart, 5)
    }

    func testOutsideWindow() {
        let base = date(2026, 9, 26, 14, 30)
        let history = [tx(.expense, 4560, base)]
        let match = DuplicateGuard.findDuplicate(of: .expense,
                                                 amountCents: 4560,
                                                 date: base.addingTimeInterval(11 * 60),
                                                 in: history)
        XCTAssertNil(match)
    }

    func testAmountMustMatch() {
        let base = date(2026, 9, 26, 14, 30)
        let history = [tx(.expense, 4560, base)]
        XCTAssertNil(DuplicateGuard.findDuplicate(of: .expense, amountCents: 4559,
                                                  date: base.addingTimeInterval(60), in: history))
    }

    func testKindMustMatch() {
        let base = date(2026, 9, 26, 14, 30)
        let history = [tx(.expense, 4560, base)]
        XCTAssertNil(DuplicateGuard.findDuplicate(of: .income, amountCents: 4560,
                                                  date: base.addingTimeInterval(60), in: history))
    }

    func testTransferMatchesTransfer() {
        let base = date(2026, 9, 26, 14, 30)
        let history = [tx(.transfer, 50000, base)]
        XCTAssertNotNil(DuplicateGuard.findDuplicate(of: .transfer, amountCents: 50000,
                                                     date: base.addingTimeInterval(120), in: history))
    }

    func testPicksClosestMatch() {
        let anchor = date(2026, 9, 26, 15, 0)
        let history = [
            tx(.expense, 4560, anchor.addingTimeInterval(-8 * 60)),
            tx(.expense, 4560, anchor.addingTimeInterval(-3 * 60)),
        ]
        let match = DuplicateGuard.findDuplicate(of: .expense, amountCents: 4560, date: anchor, in: history)
        XCTAssertEqual(match?.minutesApart, 3)
    }

    func testExcludeID() {
        let existing = tx(.expense, 4560, date(2026, 9, 26, 14, 30))
        let match = DuplicateGuard.findDuplicate(of: .expense, amountCents: 4560,
                                                 date: date(2026, 9, 26, 14, 35),
                                                 in: [existing],
                                                 excludeID: existing.id)
        XCTAssertNil(match)
    }

    func testExcludedSources() {
        let billTx = tx(.expense, 4560, date(2026, 9, 26, 14, 35), source: .bill)
        let match = DuplicateGuard.findDuplicate(of: .expense, amountCents: 4560,
                                                 date: date(2026, 9, 26, 14, 30),
                                                 in: [billTx],
                                                 excludedSources: [.bill])
        XCTAssertNil(match)
    }

    // MARK: - 决策

    private func sampleMatch() -> DuplicateMatch {
        DuplicateMatch(id: UUID(), kind: .expense, amountCents: 4560,
                       date: date(2026, 9, 26, 14, 30),
                       title: "餐饮", source: .manual, minutesApart: 3)
    }

    func testManualDecisions() {
        let match = sampleMatch()

        DuplicateGuard.sensitivity = .off
        if case .allow = DuplicateGuard.manualDecision(for: match) {} else { XCTFail("off 应放行") }

        DuplicateGuard.sensitivity = .confirm
        if case .confirm = DuplicateGuard.manualDecision(for: match) {} else { XCTFail("confirm 应弹确认") }
        if case .allow = DuplicateGuard.manualDecision(for: nil) {} else { XCTFail("无命中应放行") }

        DuplicateGuard.sensitivity = .block
        if case .block = DuplicateGuard.manualDecision(for: match) {} else { XCTFail("block 应阻止") }

        DuplicateGuard.sensitivity = .confirm // 恢复默认
    }

    func testAutoDecisions() {
        let match = sampleMatch()

        DuplicateGuard.sensitivity = .off
        if case .post = DuplicateGuard.autoDecision(for: match) {} else { XCTFail("off 应入账") }

        DuplicateGuard.sensitivity = .confirm
        if case .skip = DuplicateGuard.autoDecision(for: match) {} else { XCTFail("自动遇疑似重复应跳过") }
        if case .post = DuplicateGuard.autoDecision(for: nil) {} else { XCTFail("无命中应入账") }

        DuplicateGuard.sensitivity = .confirm // 恢复默认
    }

    // MARK: - 截图指纹

    func testFingerprintStore() {
        let suiteName = "qingji.fingerprint.tests"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)

        let fp = ScreenshotFingerprintStore.fingerprint(amountCents: 4560,
                                                        pageDate: date(2026, 9, 26, 14, 30),
                                                        merchant: "美团")
        XCTAssertFalse(ScreenshotFingerprintStore.contains(fp, defaults: suite))

        ScreenshotFingerprintStore.insert(fp, defaults: suite)
        XCTAssertTrue(ScreenshotFingerprintStore.contains(fp, defaults: suite))

        // 同页不同秒 → 同一指纹（页面时间按分钟粒度）
        let samePage = ScreenshotFingerprintStore.fingerprint(amountCents: 4560,
                                                              pageDate: date(2026, 9, 26, 14, 30).addingTimeInterval(20),
                                                              merchant: "美团")
        XCTAssertTrue(ScreenshotFingerprintStore.contains(samePage, defaults: suite))

        // 不同金额 → 不同指纹
        let different = ScreenshotFingerprintStore.fingerprint(amountCents: 9900,
                                                               pageDate: date(2026, 9, 26, 14, 30),
                                                               merchant: "美团")
        XCTAssertFalse(ScreenshotFingerprintStore.contains(different, defaults: suite))

        // 过期清理：写入 2020 年的时间戳，按 7 天有效期应被清除
        ScreenshotFingerprintStore.insert("expired-fp", now: date(2020, 1, 1), defaults: suite)
        XCTAssertFalse(ScreenshotFingerprintStore.contains("expired-fp", defaults: suite))
    }

    // MARK: - 三层导入查重

    func testBillDedupLayers() {
        let ocrTx = tx(.expense, 1990, date(2026, 9, 1, 12, 30), source: .ocr)
        ocrTx.externalID = ""
        let billTx = tx(.expense, 2500, date(2026, 9, 1, 12, 33), source: .bill)
        billTx.externalID = "B-001"

        let context = BillDedup.makeContext(for: [ocrTx, billTx])

        // ① 流水号精确
        let sameID = ParsedBillRow(externalID: "B-001",
                                   date: date(2026, 9, 1, 12, 33),
                                   amountCents: 2500, kind: .expense,
                                   counterparty: "a", product: "b", note: "", payMethod: "")
        XCTAssertTrue(BillDedup.isDuplicate(sameID, context: context))

        // ② 分钟精确（同方向+同金额+同一分钟）
        let sameMinute = ParsedBillRow(externalID: "",
                                       date: date(2026, 9, 1, 12, 30).addingTimeInterval(20),
                                       amountCents: 1990, kind: .expense,
                                       counterparty: "a", product: "b", note: "", payMethod: "")
        XCTAssertTrue(BillDedup.isDuplicate(sameMinute, context: context))

        // ③ 窗口：5 分钟内的同额非 bill 来源账目 → 重复（截图/手动流互斥）
        let nearOCR = ParsedBillRow(externalID: "",
                                    date: date(2026, 9, 1, 12, 35),
                                    amountCents: 1990, kind: .expense,
                                    counterparty: "a", product: "b", note: "", payMethod: "")
        XCTAssertTrue(BillDedup.isDuplicate(nearOCR, context: context))

        // ③' bill↔bill 近距离同额 → 不算重复（防误杀真实账单行）
        let nearBill = ParsedBillRow(externalID: "B-002",
                                     date: date(2026, 9, 1, 12, 35),
                                     amountCents: 2500, kind: .expense,
                                     counterparty: "a", product: "b", note: "", payMethod: "")
        XCTAssertFalse(BillDedup.isDuplicate(nearBill, context: context))

        // 窗口外 → 不重复
        let farAway = ParsedBillRow(externalID: "",
                                    date: date(2026, 9, 1, 13, 0),
                                    amountCents: 1990, kind: .expense,
                                    counterparty: "a", product: "b", note: "", payMethod: "")
        XCTAssertFalse(BillDedup.isDuplicate(farAway, context: context))
    }
}

/// 自动入账日志（@MainActor 存储）
@MainActor
final class AutoPostStoreTests: XCTestCase {

    func testRecordUndoAndSkip() {
        let suiteName = "qingji.autopost.tests"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
        let store = AutoPostStore(defaults: suite)

        XCTAssertTrue(store.entries.isEmpty)

        let txID = UUID()
        store.recordPosted(txID: txID, kind: .expense, amountCents: 4560,
                           date: Date.now, note: "美团外卖")
        store.recordSkipped(kind: .expense, amountCents: 1990,
                            date: Date.now, note: "瑞幸咖啡")

        XCTAssertEqual(store.entries.count, 2)
        XCTAssertEqual(store.entries.first?.status, .skippedDuplicate) // 最新的在前

        // 撤销：返回待删 txID 并标记状态
        let postedEntry = store.entries.first { $0.status == .posted }
        let undoneTxID = store.markUndone(postedEntry!.id)
        XCTAssertEqual(undoneTxID, txID)
        XCTAssertEqual(store.entries.first { $0.id == postedEntry!.id }?.status, .undone)

        // 重复撤销无效
        XCTAssertNil(store.markUndone(postedEntry!.id))

        // 持久化：新实例可读回
        let reloaded = AutoPostStore(defaults: suite)
        XCTAssertEqual(reloaded.entries.count, 2)
    }
}
