import XCTest
@testable import QingJi

/// F-12 截图入账：待确认暂存 + 设置
@MainActor
final class CaptureTests: XCTestCase {

    func testPendingCaptureStoreAddFindRemove() {
        let suiteName = "qingji.capture.tests"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
        let store = PendingCaptureStore(defaults: suite)

        XCTAssertNil(store.find(UUID()))

        let capture = store.add(amountCents: 4560, date: Date.now, note: "美团外卖")
        XCTAssertEqual(store.find(capture.id)?.note, "美团外卖")
        XCTAssertEqual(store.find(capture.id)?.amountCents, 4560)

        store.remove(capture.id)
        XCTAssertNil(store.find(capture.id))
    }

    func testPendingCaptureCapacityCap() {
        let suiteName = "qingji.capture.capacity.tests"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
        let store = PendingCaptureStore(defaults: suite)

        var firstID: UUID?
        var keepID: UUID?
        for index in 0..<25 {
            let capture = store.add(amountCents: Int64(index), date: Date.now, note: "n\(index)")
            if index == 0 { firstID = capture.id }
            if index == 5 { keepID = capture.id }
        }

        // 容量 20：最老的（第 1 条）被裁剪，容量内的（第 6 条）保留
        XCTAssertNotNil(firstID)
        XCTAssertNil(store.find(firstID!))
        XCTAssertEqual(store.find(keepID!)?.note, "n5")
    }

    func testPendingCaptureTTLExpiredPurged() throws {
        let suiteName = "qingji.capture.ttl.tests"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)

        // 手工写入一条已过期（created 25 小时前）的暂存
        let old = PendingCapture(id: UUID(),
                                 amountCents: 100,
                                 date: Date.now.addingTimeInterval(-100_000),
                                 note: "old",
                                 createdAt: Date.now.addingTimeInterval(-25 * 3600))
        let data = try JSONEncoder().encode([old])
        suite.set(data, forKey: "qingji.capture.pending")

        let store = PendingCaptureStore(defaults: suite)
        XCTAssertNil(store.find(old.id)) // 初始化时过期清理生效
    }

    func testCaptureSettingsDefaultOff() {
        UserDefaults.standard.removeObject(forKey: "qingji.capture.autoSave")
        XCTAssertFalse(CaptureSettings.autoSave)

        CaptureSettings.autoSave = true
        XCTAssertTrue(CaptureSettings.autoSave)

        CaptureSettings.autoSave = false
        XCTAssertFalse(CaptureSettings.autoSave)
    }
}
