import Foundation
import UIKit
import UserNotifications
import SwiftData

/// 截图入账设置（文档 F-12）
enum CaptureSettings {
    private static let autoSaveKey = "qingji.capture.autoSave"

    /// false = 确认式（默认：通知里点「入账」）；true = 静默自动入账
    static var autoSave: Bool {
        get { UserDefaults.standard.bool(forKey: autoSaveKey) }
        set { UserDefaults.standard.set(newValue, forKey: autoSaveKey) }
    }
}

/// 待确认的截图账目（确认式暂存；通知按钮触发落库；24 小时未处理自动清理）
struct PendingCapture: Codable, Identifiable {
    let id: UUID
    let amountCents: Int64
    let date: Date
    let note: String
    let createdAt: Date
}

/// 待确认暂存仓
@MainActor
final class PendingCaptureStore {
    static let shared = PendingCaptureStore()
    private static let key = "qingji.capture.pending"
    private static let capacity = 20
    private static let ttl: TimeInterval = 24 * 3600

    private let defaults: UserDefaults
    private var entries: [PendingCapture] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([PendingCapture].self, from: data) else { return }
        entries = decoded
        purgeExpired()
    }

    func add(amountCents: Int64, date: Date, note: String) -> PendingCapture {
        purgeExpired()
        let capture = PendingCapture(id: UUID(), amountCents: amountCents, date: date, note: note, createdAt: .now)
        entries.insert(capture, at: 0)
        if entries.count > Self.capacity {
            entries = Array(entries.prefix(Self.capacity))
        }
        persist()
        return capture
    }

    func find(_ id: UUID) -> PendingCapture? {
        entries.first { $0.id == id }
    }

    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    private func purgeExpired() {
        let cutoff = Date.now.addingTimeInterval(-Self.ttl)
        let before = entries.count
        entries.removeAll { $0.createdAt < cutoff }
        if entries.count != before {
            persist()
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: Self.key)
        }
    }
}

/// 确认卡通知 + 按钮回调 + 静默入账（文档 F-12）
enum CaptureNotificationHandler {

    static let categoryIdentifier = "QJ_CAPTURE"
    static let confirmActionIdentifier = "QJ_CONFIRM"
    static let ignoreActionIdentifier = "QJ_IGNORE"

    static func registerCategories() {
        let confirm = UNNotificationAction(identifier: confirmActionIdentifier,
                                           title: "入账",
                                           options: [.authenticationRequired])
        let ignore = UNNotificationAction(identifier: ignoreActionIdentifier,
                                          title: "忽略",
                                          options: [])
        let category = UNNotificationCategory(identifier: categoryIdentifier,
                                              actions: [confirm, ignore],
                                              intentIdentifiers: [],
                                              options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        default:
            return false
        }
    }

    /// 发确认卡；返回 false 表示通知权限不可用（调用方降级处理）
    @MainActor
    static func postConfirmNotification(_ capture: PendingCapture) async throws -> Bool {
        guard await requestAuthorizationIfNeeded() else { return false }
        registerCategories()

        let content = UNMutableNotificationContent()
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 HH:mm"
        content.title = "检测到支付 \(Money.string(fromCents: capture.amountCents))"
        content.body = "\(capture.note) · \(formatter.string(from: capture.date)) — 点「入账」记下这笔"
        content.categoryIdentifier = categoryIdentifier
        content.sound = .default

        let request = UNNotificationRequest(identifier: capture.id.uuidString, content: content, trigger: nil)
        try await UNUserNotificationCenter.current().add(request)
        return true
    }

    /// 通知按钮回调：确认→落库；忽略→仅清理
    @MainActor
    static func handle(actionIdentifier: String, notificationID: String) {
        guard let id = UUID(uuidString: notificationID),
              let capture = PendingCaptureStore.shared.find(id) else { return }
        defer { PendingCaptureStore.shared.remove(id) }
        guard actionIdentifier == confirmActionIdentifier else { return }
        postDirectly(amountCents: capture.amountCents, date: capture.date, note: capture.note)
    }

    /// 静默落库（自动模式与通知确认共用），来源 .ocr，写入自动入账日志
    @MainActor
    static func postDirectly(amountCents: Int64, date: Date, note: String) {
        let context = ModelContext(AppDatabase.shared)
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        guard let account = accounts.first(where: { !$0.isArchived }) else { return }

        let tx = Transaction(kind: .expense,
                             amountCents: amountCents,
                             date: date,
                             account: account,
                             note: note,
                             source: .ocr)
        context.insert(tx)
        try? context.save()
        AutoPostStore.shared.recordPosted(txID: tx.id, kind: .expense,
                                          amountCents: amountCents, date: date, note: note)
    }
}
