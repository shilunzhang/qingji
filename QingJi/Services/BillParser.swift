import Foundation
import CoreFoundation

/// 账单来源
enum BillSource: String {
    case alipay = "支付宝"
    case wechat = "微信"
}

/// 账单导入解析出的一行（文档 F-10）
struct ParsedBillRow {
    var externalID: String = ""
    var date: Date
    var amountCents: Int64
    var kind: TxKind
    var counterparty: String
    var product: String
    var note: String
    var payMethod: String
}

struct BillParseResult {
    let source: BillSource
    let rows: [ParsedBillRow]
    /// 因不计收支/状态无效等原因跳过的行数
    let skippedLines: Int
}

enum BillParseError: LocalizedError {
    case unrecognizedFormat

    var errorDescription: String? {
        switch self {
        case .unrecognizedFormat:
            return "无法识别账单格式，请使用支付宝/微信官方导出的 CSV 原始文件（不要用 Excel 另存）"
        }
    }
}

/// 支付宝 / 微信账单 CSV 解析器。表头动态定位，兼容多版本导出格式。
enum BillParser {

    // MARK: - 入口

    static func parse(data: Data) throws -> BillParseResult {
        let content = decode(data)
        if content.contains("微信支付账单明细") || content.contains("商户单号") || content.contains("当前状态") {
            return try parseWeChat(content)
        }
        if content.contains("支付宝") || content.contains("商品名称") || content.contains("交易号") {
            return try parseAlipay(content)
        }
        throw BillParseError.unrecognizedFormat
    }

    // MARK: - 编码（支付宝导出为 GBK/GB18030）

    static func decode(_ data: Data) -> String {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        if let gb = String(data: data, encoding: Self.gb18030) { return gb }
        return String(decoding: data, as: UTF8.self)
    }

    private static let gb18030: String.Encoding = {
        let encoding = CFStringEncodings.GB_18030_2000
        let ns = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(encoding.rawValue))
        return String.Encoding(rawValue: ns)
    }()

    // MARK: - 微信

    private static func parseWeChat(_ content: String) throws -> BillParseResult {
        let lines = splitLines(content)
        guard let headerIndex = lines.firstIndex(where: { line in
            let cells = parseCSVLine(line)
            return contains(cells, "交易时间") && contains(cells, "当前状态")
        }) else { throw BillParseError.unrecognizedFormat }

        let header = parseCSVLine(lines[headerIndex])
        let dateI = columnIndex(header, names: ["交易时间"])
        let partyI = columnIndex(header, names: ["交易对方"])
        let productI = columnIndex(header, names: ["商品"])
        let directionI = columnIndex(header, names: ["收/支"])
        let amountI = columnIndex(header, names: ["金额"])
        let methodI = columnIndex(header, names: ["支付方式"])
        let statusI = columnIndex(header, names: ["当前状态"])
        let externalIDI = columnIndex(header, names: ["交易单号"])
        let noteI = columnIndex(header, names: ["备注"])
        guard let dateI, let directionI, let amountI else { throw BillParseError.unrecognizedFormat }

        let maxIndex = [dateI, directionI, amountI, statusI, partyI, productI, externalIDI, methodI, noteI]
            .compactMap { $0 }.max() ?? 0

        var rows: [ParsedBillRow] = []
        var skipped = 0
        for line in lines[(headerIndex + 1)...] {
            let cells = parseCSVLine(line)
            guard cells.count > maxIndex else {
                if !line.trimmingCharacters(in: .whitespaces).isEmpty { skipped += 1 }
                continue
            }
            guard let kind = directionKind(value(cells, directionI)),
                  let amountCents = cents(value(cells, amountI)),
                  let date = parseDate(value(cells, dateI)),
                  isCountableStatus(value(cells, statusI)) else {
                skipped += 1
                continue
            }
            rows.append(ParsedBillRow(
                externalID: value(cells, externalIDI),
                date: date,
                amountCents: amountCents,
                kind: kind,
                counterparty: value(cells, partyI),
                product: value(cells, productI),
                note: noteValue(value(cells, noteI)),
                payMethod: value(cells, methodI)))
        }
        return BillParseResult(source: .wechat, rows: rows, skippedLines: skipped)
    }

    // MARK: - 支付宝

    private static func parseAlipay(_ content: String) throws -> BillParseResult {
        let lines = splitLines(content)
        guard let headerIndex = lines.firstIndex(where: { line in
            let cells = parseCSVLine(line)
            return contains(cells, "交易对方") && contains(cells, "收/支") && !contains(cells, "当前状态")
        }) else { throw BillParseError.unrecognizedFormat }

        let header = parseCSVLine(lines[headerIndex])
        let dateI = columnIndex(header, names: ["交易创建时间", "交易时间"])
        let partyI = columnIndex(header, names: ["交易对方"])
        let productI = columnIndex(header, names: ["商品名称", "商品说明", "商品"])
        let directionI = columnIndex(header, names: ["收/支"])
        let amountI = columnIndex(header, names: ["金额（元）", "金额(元)", "金额"])
        let methodI = columnIndex(header, names: ["收/付款方式", "付款方式"])
        let statusI = columnIndex(header, names: ["交易状态"])
        let externalIDI = columnIndex(header, names: ["交易号", "交易订单号"])
        let noteI = columnIndex(header, names: ["备注"])
        guard let dateI, let directionI, let amountI else { throw BillParseError.unrecognizedFormat }

        let maxIndex = [dateI, directionI, amountI, statusI, partyI, productI, externalIDI, methodI, noteI]
            .compactMap { $0 }.max() ?? 0

        var rows: [ParsedBillRow] = []
        var skipped = 0
        for line in lines[(headerIndex + 1)...] {
            let cells = parseCSVLine(line)
            guard cells.count > maxIndex else {
                if !line.trimmingCharacters(in: .whitespaces).isEmpty { skipped += 1 }
                continue
            }
            guard let kind = directionKind(value(cells, directionI)),
                  let amountCents = cents(value(cells, amountI)),
                  let date = parseDate(value(cells, dateI)),
                  isCountableStatus(value(cells, statusI)) else {
                skipped += 1
                continue
            }
            rows.append(ParsedBillRow(
                externalID: value(cells, externalIDI),
                date: date,
                amountCents: amountCents,
                kind: kind,
                counterparty: value(cells, partyI),
                product: value(cells, productI),
                note: noteValue(value(cells, noteI)),
                payMethod: value(cells, methodI)))
        }
        return BillParseResult(source: .alipay, rows: rows, skippedLines: skipped)
    }

    // MARK: - 工具

    static func splitLines(_ content: String) -> [String] {
        content.components(separatedBy: .newlines)
    }

    /// 单行 CSV 解析（处理双引号包裹的逗号）
    static func parseCSVLine(_ line: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var inQuotes = false
        for ch in line {
            if inQuotes {
                if ch == "\"" { inQuotes = false } else { current.append(ch) }
            } else {
                if ch == "\"" {
                    inQuotes = true
                } else if ch == "," {
                    cells.append(current)
                    current = ""
                } else {
                    current.append(ch)
                }
            }
        }
        cells.append(current)
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func contains(_ cells: [String], _ keyword: String) -> Bool {
        cells.contains { $0.trimmingCharacters(in: .whitespaces) == keyword }
    }

    /// 按名称顺序匹配列索引（前缀匹配，如 "金额（元）" 匹配 "金额"）
    static func columnIndex(_ cells: [String], names: [String]) -> Int? {
        let trimmed = cells.map { $0.trimmingCharacters(in: .whitespaces) }
        for name in names {
            if let index = trimmed.firstIndex(where: { $0 == name || $0.hasPrefix(name) }) {
                return index
            }
        }
        return nil
    }

    private static func value(_ cells: [String], _ index: Int?) -> String {
        guard let index, index < cells.count else { return "" }
        return cells[index].trimmingCharacters(in: .whitespaces)
    }

    private static func directionKind(_ direction: String) -> TxKind? {
        if direction.contains("支出") { return .expense }
        if direction.contains("收入") { return .income }
        return nil
    }

    /// 只导入确定性收支；退款/未完成/不计收支剔除（文档 F-10 噪声剔除）
    private static func isCountableStatus(_ status: String) -> Bool {
        let s = status.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return false }
        if s.contains("退款") || s.contains("关闭") || s.contains("撤销")
            || s.contains("等待") || s.contains("失败") || s.contains("冻结") { return false }
        return s.contains("成功")
            || s == "已存入零钱" || s == "已收款" || s == "已收钱" || s == "对方已收钱"
    }

    /// "¥1,234.00" / "45.60" 等 -> 分
    private static func cents(_ raw: String) -> Int64? {
        let cleaned = String(raw.filter { $0.isNumber || $0 == "." })
        guard !cleaned.isEmpty else { return nil }
        return Money.cents(fromString: cleaned)
    }

    private static func noteValue(_ raw: String) -> String {
        raw == "/" || raw == "-" ? "" : raw
    }

    private static var formatterCache: [String: DateFormatter] = [:]
    private static let dateFormats = [
        "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm",
        "yyyy/MM/dd HH:mm:ss", "yyyy/MM/dd HH:mm",
        "yyyy年M月d日 HH:mm:ss", "yyyy年M月d日 HH:mm",
    ]

    static func parseDate(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        for format in dateFormats {
            let formatter: DateFormatter
            if let cached = formatterCache[format] {
                formatter = cached
            } else {
                formatter = DateFormatter()
                formatter.dateFormat = format
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatterCache[format] = formatter
            }
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return nil
    }
}

/// 导入查重（文档 F-10）：交易单号精确 + 时间(分钟)/金额/方向 模糊
enum BillDedup {

    struct Keys {
        let externalIDs: Set<String>
        let fuzzy: Set<String>
    }

    static func keys(for transactions: [Transaction]) -> Keys {
        var externalIDs: Set<String> = []
        var fuzzy: Set<String> = []
        for tx in transactions {
            if !tx.externalID.isEmpty { externalIDs.insert(tx.externalID) }
            fuzzy.insert(fuzzyKey(kind: tx.type, date: tx.date, amountCents: tx.amountCents))
        }
        return Keys(externalIDs: externalIDs, fuzzy: fuzzy)
    }

    static func fuzzyKey(kind: TxKind, date: Date, amountCents: Int64) -> String {
        let minute = Int(date.timeIntervalSince1970 / 60)
        return "\(kind.rawValue)|\(minute)|\(amountCents)"
    }

    static func fuzzyKey(of row: ParsedBillRow) -> String {
        fuzzyKey(kind: row.kind, date: row.date, amountCents: row.amountCents)
    }
}
