import Foundation
import SwiftData

/// 账户类型（文档 §4.2）
enum AccountKind: String, Codable, CaseIterable, Identifiable {
    case cash, bank, alipay, wechat, credit
    var id: String { rawValue }

    var title: String {
        switch self {
        case .cash: return "现金"
        case .bank: return "储蓄卡"
        case .alipay: return "支付宝"
        case .wechat: return "微信"
        case .credit: return "信用卡"
        }
    }

    var defaultIcon: String {
        switch self {
        case .cash: return "banknote"
        case .bank: return "building.columns"
        case .alipay: return "qrcode"
        case .wechat: return "message"
        case .credit: return "creditcard"
        }
    }

    var isCredit: Bool { self == .credit }
}

/// 账户。余额不落库，由 LedgerService 实时计算（文档 §3.3）。
@Model
final class Account {
    var id: UUID = UUID()
    var name: String = ""
    /// AccountKind.rawValue
    var kindRaw: String = AccountKind.cash.rawValue
    /// SF Symbol 名
    var icon: String = "banknote"
    /// 十六进制颜色（RRGGBB）
    var colorHex: String = "4A90D9"
    /// 期初余额（分）。信用卡欠款表现为负余额
    var initialBalanceCents: Int64 = 0
    /// 信用额度（分），仅信用卡
    var creditLimitCents: Int64 = 0
    /// 账单日（1-31），仅信用卡
    var billingDay: Int = 1
    /// 还款日（1-31），仅信用卡
    var dueDay: Int = 1
    var sortOrder: Int = 0
    var isArchived: Bool = false
    var createdAt: Date = Date.now

    var kind: AccountKind { AccountKind(rawValue: kindRaw) ?? .cash }

    init(name: String,
         kind: AccountKind,
         icon: String? = nil,
         colorHex: String = "4A90D9",
         initialBalanceCents: Int64 = 0,
         creditLimitCents: Int64 = 0,
         billingDay: Int = 1,
         dueDay: Int = 1,
         sortOrder: Int = 0) {
        self.name = name
        self.kindRaw = kind.rawValue
        self.icon = icon ?? kind.defaultIcon
        self.colorHex = colorHex
        self.initialBalanceCents = initialBalanceCents
        self.creditLimitCents = creditLimitCents
        self.billingDay = billingDay
        self.dueDay = dueDay
        self.sortOrder = sortOrder
    }
}
