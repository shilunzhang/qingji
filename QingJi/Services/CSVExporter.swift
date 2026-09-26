import Foundation

/// CSV 导出（文档 F-08）：UTF-8 BOM，Excel 中文不乱码。
enum CSVExporter {

    static func export(transactions: [Transaction]) -> URL? {
        var lines: [String] = ["日期,类型,分类,账户,转入账户,金额,备注"]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        let sorted = transactions.sorted { $0.date < $1.date }
        for tx in sorted {
            let amount = plainYuanString(tx.amountCents)
            let row = [
                formatter.string(from: tx.date),
                tx.type.title,
                tx.category?.name ?? "",
                tx.account?.name ?? "",
                tx.toAccount?.name ?? "",
                amount,
                tx.note,
            ]
            lines.append(row.map(escape).joined(separator: ","))
        }

        let csv = "\u{FEFF}" + lines.joined(separator: "\n")
        let formatter2 = DateFormatter()
        formatter2.dateFormat = "yyyyMMdd_HHmmss"
        let fileName = "轻记账单_\(formatter2.string(from: Date())).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try csv.data(using: .utf8)?.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    /// 纯金额（无货币符号），如 "1234.50"
    static func plainYuanString(_ cents: Int64) -> String {
        let absCents = abs(cents)
        return String(format: "%lld.%02lld", absCents / 100, absCents % 100)
    }

    private static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
