import Foundation

/// 分类统计结果（文档 F-03）
struct CategoryStat: Identifiable {
    /// 分类 id 字符串；无分类流水聚合为 "none"
    let id: String
    let name: String
    let icon: String
    let colorHex: String
    let totalCents: Int64
    /// 占比 0-1
    let percent: Double
}

/// 按日聚合结果
struct DayTotal: Identifiable {
    let date: Date
    let totalCents: Int64
    var id: Date { date }
}

/// 统计聚合，纯函数。
enum StatsService {

    static func totalCents(_ transactions: [Transaction], kind: TxKind) -> Int64 {
        transactions.filter { $0.type == kind }.reduce(0) { $0 + $1.amountCents }
    }

    /// 按分类聚合，降序；percent 相对该 kind 总额
    static func byCategory(_ transactions: [Transaction], kind: TxKind) -> [CategoryStat] {
        let matched = transactions.filter { $0.type == kind }
        let total = matched.reduce(Int64(0)) { $0 + $1.amountCents }
        guard total > 0 else { return [] }

        var buckets: [String: (name: String, icon: String, hex: String, sum: Int64)] = [:]
        for tx in matched {
            let key = tx.category.map { $0.id.uuidString } ?? "none"
            let name = tx.category?.name ?? "未分类"
            let icon = tx.category?.icon ?? "ellipsis"
            let hex = tx.category?.colorHex ?? "9E9E9E"
            if var existing = buckets[key] {
                existing.sum += tx.amountCents
                buckets[key] = existing
            } else {
                buckets[key] = (name, icon, hex, tx.amountCents)
            }
        }
        return buckets.map { key, value in
            CategoryStat(id: key,
                         name: value.name,
                         icon: value.icon,
                         colorHex: value.hex,
                         totalCents: value.sum,
                         percent: Double(value.sum) / Double(total))
        }
        .sorted { $0.totalCents > $1.totalCents }
    }

    /// 按自然日聚合（仅返回区间内有流水的日子），升序
    static func byDay(_ transactions: [Transaction],
                      kind: TxKind,
                      in range: (start: Date, end: Date),
                      calendar: Calendar = .current) -> [DayTotal] {
        let matched = transactions.filter { $0.type == kind && $0.date >= range.start && $0.date <= range.end }
        var buckets: [Date: Int64] = [:]
        for tx in matched {
            let day = calendar.startOfDay(for: tx.date)
            buckets[day, default: 0] += tx.amountCents
        }
        return buckets.map { DayTotal(date: $0.key, totalCents: $0.value) }
            .sorted { $0.date < $1.date }
    }

    /// 饼图数据：Top N + 「其他」
    static func pieSlices(_ stats: [CategoryStat], topN: Int = 8) -> [CategoryStat] {
        guard stats.count > topN else { return stats }
        let top = Array(stats.prefix(topN))
        let restSum = stats.dropFirst(topN).reduce(Int64(0)) { $0 + $1.totalCents }
        let total = stats.reduce(Int64(0)) { $0 + $1.totalCents }
        guard total > 0 else { return stats }
        let other = CategoryStat(id: "other",
                                 name: "其他",
                                 icon: "ellipsis.circle",
                                 colorHex: "B0BEC5",
                                 totalCents: restSum,
                                 percent: Double(restSum) / Double(total))
        return top + [other]
    }
}
