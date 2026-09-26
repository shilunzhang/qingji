import Foundation
import SwiftData

/// 自动入账日志条目状态（文档 F-12/F-14）
enum AutoPostStatus: String, Codable {
    case posted            // 已入账（可撤销）
    case skippedDuplicate  // 防重闸门跳过
    case undone            // 已撤销
}

struct AutoPostEntry: Codable, Identifiable {
    let id: UUID
    let txID: UUID?
    let kindRaw: String
    let amountCents: Int64
    /// 交易时间
    let date: Date
    let note: String
    /// 记录时间
    let postedAt: Date
    var statusRaw: String

    var kind: TxKind { TxKind(rawValue: kindRaw) ?? .expense }
    var status: AutoPostStatus { AutoPostStatus(rawValue: statusRaw) ?? .posted }
}

/// 自动入账日志（文档 F-14 第 5 道防线：可撤销兜底）。
/// UserDefaults 滚动存储，保留最近 200 条。
@MainActor
final class AutoPostStore: ObservableObject {

    static let shared = AutoPostStore()
    private static let key = "qingji.autopost.log"
    private static let capacity = 200

    private let defaults: UserDefaults

    @Published private(set) var entries: [AutoPostEntry] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([AutoPostEntry].self, from: data) else { return }
        entries = decoded.sorted { $0.postedAt > $1.postedAt }
    }

    private func persist() {
        let trimmed = Array(entries.prefix(Self.capacity))
        if let data = try? JSONEncoder().encode(trimmed) {
            defaults.set(data, forKey: Self.key)
        }
    }

    func recordPosted(txID: UUID, kind: TxKind, amountCents: Int64, date: Date, note: String) {
        insert(entry: AutoPostEntry(id: UUID(), txID: txID, kindRaw: kind.rawValue,
                                    amountCents: amountCents, date: date, note: note,
                                    postedAt: Date.now, statusRaw: AutoPostStatus.posted.rawValue))
    }

    func recordSkipped(kind: TxKind, amountCents: Int64, date: Date, note: String) {
        insert(entry: AutoPostEntry(id: UUID(), txID: nil, kindRaw: kind.rawValue,
                                    amountCents: amountCents, date: date, note: note,
                                    postedAt: Date.now, statusRaw: AutoPostStatus.skippedDuplicate.rawValue))
    }

    /// 撤销：把条目标记为已撤销，返回待删除的账目 id（删除动作由调用方在数据库执行）
    @discardableResult
    func markUndone(_ entryID: UUID) -> UUID? {
        guard let index = entries.firstIndex(where: { $0.id == entryID }),
              entries[index].status == .posted,
              let txID = entries[index].txID else { return nil }
        entries[index].statusRaw = AutoPostStatus.undone.rawValue
        persist()
        return txID
    }

    private func insert(entry: AutoPostEntry) {
        entries.insert(entry, at: 0)
        persist()
    }
}
