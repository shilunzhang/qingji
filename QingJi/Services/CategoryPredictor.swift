import Foundation

/// 分类预测（文档 F-01 智能默认 / 9.4 技术债：M3 换端侧模型）
/// M1 策略：历史「同时段桶」高频分类加权 + 全局频次，纯函数。
enum CategoryPredictor {

    /// 时段桶：0 深夜(0-5) 1 早餐(6-10) 2 午间(11-13) 3 下午(14-17) 4 晚间(18-23)
    static func bucket(of date: Date, calendar: Calendar = .current) -> Int {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 0...5: return 0
        case 6...10: return 1
        case 11...13: return 2
        case 14...17: return 3
        default: return 4
        }
    }

    /// 推荐排序列表：优先返回最近 60 天内「同时段桶」高频分类，再按全局频次
    static func ranked(categories: [Category],
                       transactions: [Transaction],
                       kind: TxKind,
                       at date: Date,
                       calendar: Calendar = .current) -> [Category] {
        let candidates = categories.filter {
            (kind == .expense && $0.kindRaw == CategoryKind.expense.rawValue)
                || (kind == .income && $0.kindRaw == CategoryKind.income.rawValue)
        }
        guard !candidates.isEmpty else { return [] }

        let bucketValue = bucket(of: date, calendar: calendar)
        let cutoff = calendar.date(byAdding: .day, value: -60, to: date) ?? date

        var bucketScore: [UUID: Int] = [:]
        var globalScore: [UUID: Int] = [:]
        for tx in transactions where tx.type == kind {
            guard let cat = tx.category else { continue }
            globalScore[cat.id, default: 0] += 1
            if tx.date >= cutoff && bucket(of: tx.date, calendar: calendar) == bucketValue {
                bucketScore[cat.id, default: 0] += 1
            }
        }

        return candidates.sorted { a, b in
            let sa = bucketScore[a.id, default: 0] * 10 + globalScore[a.id, default: 0]
            let sb = bucketScore[b.id, default: 0] * 10 + globalScore[b.id, default: 0]
            if sa != sb { return sa > sb }
            return a.sortOrder < b.sortOrder
        }
    }

    /// 单个推荐分类；完全没有历史记录时不做无根据的预选（返回 nil）
    static func topCategory(categories: [Category],
                            transactions: [Transaction],
                            kind: TxKind,
                            at date: Date,
                            calendar: Calendar = .current) -> Category? {
        let hasHistory = transactions.contains { $0.type == kind && $0.category != nil }
        guard hasHistory else { return nil }
        return ranked(categories: categories, transactions: transactions, kind: kind, at: date, calendar: calendar).first
    }
}
