import Foundation
import SwiftData

/// 周期频率（文档 F-07）
enum RecurringFrequency: String, Codable, CaseIterable, Identifiable {
    case daily, weekly, monthly, yearly
    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: return "每天"
        case .weekly: return "每周"
        case .monthly: return "每月"
        case .yearly: return "每年"
        }
    }
}

/// 周期记账规则。到期由 RecurringEngine 生成流水。
@Model
final class RecurringRule {
    var id: UUID = UUID()
    var name: String = ""
    /// TxKind.rawValue（不含 transfer）
    var kindRaw: String = TxKind.expense.rawValue
    var amountCents: Int64 = 0
    /// RecurringFrequency.rawValue
    var frequencyRaw: String = RecurringFrequency.monthly.rawValue
    /// monthly: 1-31（月末自动收敛）；weekly: 1=周一...7=周日；daily 间隔天数用 intervalDays
    var dayOfMonth: Int = 1
    var weekday: Int = 1
    var intervalDays: Int = 1
    var startDate: Date = .now
    var endDate: Date? = nil
    /// 最近一次已入账的执行日期；nil 表示尚未入过账
    var lastPostedDate: Date? = nil
    var isActive: Bool = true
    var note: String = ""
    var createdAt: Date = .now

    @Relationship var category: Category? = nil
    @Relationship var account: Account? = nil

    var kind: TxKind { TxKind(rawValue: kindRaw) ?? .expense }
    var frequency: RecurringFrequency { RecurringFrequency(rawValue: frequencyRaw) ?? .monthly }

    init(name: String,
         kind: TxKind,
         amountCents: Int64,
         frequency: RecurringFrequency,
         dayOfMonth: Int = 1,
         weekday: Int = 1,
         intervalDays: Int = 1,
         startDate: Date = .now,
         endDate: Date? = nil,
         note: String = "") {
        self.name = name
        self.kindRaw = kind.rawValue
        self.amountCents = amountCents
        self.frequencyRaw = frequency.rawValue
        self.dayOfMonth = dayOfMonth
        self.weekday = weekday
        self.intervalDays = intervalDays
        self.startDate = startDate
        self.endDate = endDate
        self.note = note
    }
}
