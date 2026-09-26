import Foundation
import SwiftData

/// 交易类型（文档 §4.1）
enum TxKind: String, Codable, CaseIterable, Identifiable {
    case expense, income, transfer
    var id: String { rawValue }

    var title: String {
        switch self {
        case .expense: return "支出"
        case .income: return "收入"
        case .transfer: return "转账"
        }
    }
}

/// 账目来源（文档 F-14：防重日志与自动入账撤销清单依赖）
enum TxSource: String, Codable, CaseIterable, Identifiable {
    case manual, ocr, album, bill, recurring
    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: return "手动"
        case .ocr: return "截图识别"
        case .album: return "相册扫描"
        case .bill: return "账单导入"
        case .recurring: return "周期记账"
        }
    }
}

/// 流水。金额以「分」存储，恒为正数，方向由 kind 决定。
@Model
final class Transaction {
    var id: UUID = UUID()
    /// TxKind.rawValue，见文档 D6
    var kind: String = TxKind.expense.rawValue
    /// 金额（分），恒为正
    var amountCents: Int64 = 0
    var currencyCode: String = "CNY"
    /// 交易时间（允许补记过去时间）
    var date: Date = Date.now
    var note: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    /// 由周期规则生成时记录来源（文档 §4.4）
    var recurringRuleID: UUID? = nil
    /// 外部流水号（账单导入的去重主键，文档 F-10）
    var externalID: String = ""
    /// 账目来源（TxSource.rawValue，文档 F-14）
    var source: String = TxSource.manual.rawValue

    @Relationship var account: Account? = nil
    @Relationship var toAccount: Account? = nil
    @Relationship var category: Category? = nil
    @Relationship(inverse: \Tag.transactions) var tags: [Tag]? = nil
    @Relationship(deleteRule: .cascade, inverse: \Attachment.transaction) var attachments: [Attachment]? = nil

    var type: TxKind { TxKind(rawValue: kind) ?? .expense }
    var txSource: TxSource { TxSource(rawValue: source) ?? .manual }
    /// 元（Decimal），仅供展示/图表
    var yuan: Decimal { Money.yuan(fromCents: amountCents) }

    init(kind: TxKind,
         amountCents: Int64,
         date: Date = Date.now,
         account: Account? = nil,
         toAccount: Account? = nil,
         category: Category? = nil,
         note: String = "",
         recurringRuleID: UUID? = nil,
         externalID: String = "",
         source: TxSource = .manual) {
        self.kind = kind.rawValue
        self.amountCents = amountCents
        self.date = date
        self.account = account
        self.toAccount = toAccount
        self.category = category
        self.note = note
        self.recurringRuleID = recurringRuleID
        self.externalID = externalID
        self.source = source.rawValue
    }

    /// 行标题：分类名 / 转账 / 未分类
    var displayTitle: String {
        switch type {
        case .transfer: return "转账"
        default: return category?.name ?? "未分类"
        }
    }
}
