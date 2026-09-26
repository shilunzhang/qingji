import Foundation
import SwiftData

/// 预算范围
enum BudgetScope: String, Codable, CaseIterable {
    case overall, category
}

/// 月度预算（文档 F-06）：总预算（scope=overall）或分类预算
@Model
final class Budget {
    var id: UUID = UUID()
    /// BudgetScope.rawValue
    var scopeRaw: String = BudgetScope.overall.rawValue
    /// 月度金额（分）
    var amountCents: Int64 = 0
    var createdAt: Date = .now

    @Relationship var category: Category? = nil

    var scope: BudgetScope { BudgetScope(rawValue: scopeRaw) ?? .overall }

    init(amountCents: Int64, category: Category? = nil) {
        self.scopeRaw = category == nil ? BudgetScope.overall.rawValue : BudgetScope.category.rawValue
        self.amountCents = amountCents
        self.category = category
    }
}
