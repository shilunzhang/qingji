import Foundation

/// 账目核心计算（文档 §3.3）。全部纯函数，便于单测。
enum LedgerService {

    /// 账户余额 = 期初 + Σ收入 − Σ支出 − Σ转出 + Σ转入
    static func balanceCents(of account: Account, transactions: [Transaction]) -> Int64 {
        var sum = account.initialBalanceCents
        let accountID = account.id
        for tx in transactions {
            switch tx.type {
            case .expense:
                if tx.account?.id == accountID { sum -= tx.amountCents }
            case .income:
                if tx.account?.id == accountID { sum += tx.amountCents }
            case .transfer:
                if tx.account?.id == accountID { sum -= tx.amountCents }
                if tx.toAccount?.id == accountID { sum += tx.amountCents }
            }
        }
        return sum
    }

    /// 净资产 = Σ 各账户余额（信用卡欠款为负自动抵扣）
    static func netWorthCents(accounts: [Account], transactions: [Transaction]) -> Int64 {
        accounts.filter { !$0.isArchived }
            .reduce(0) { $0 + balanceCents(of: $1, transactions: transactions) }
    }

    /// 区间内收支汇总
    static func totals(in transactions: [Transaction]) -> (expense: Int64, income: Int64) {
        var expense: Int64 = 0
        var income: Int64 = 0
        for tx in transactions {
            switch tx.type {
            case .expense: expense += tx.amountCents
            case .income: income += tx.amountCents
            case .transfer: break
            }
        }
        return (expense, income)
    }

    /// 区间过滤（含边界）
    static func transactions(_ transactions: [Transaction], in range: (start: Date, end: Date)) -> [Transaction] {
        transactions.filter { $0.date >= range.start && $0.date <= range.end }
    }
}
