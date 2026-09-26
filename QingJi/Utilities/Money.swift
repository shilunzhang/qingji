import Foundation

/// 金额工具。
/// 项目约定（文档 D5）：金额一律以「分」(Int64) 存储，禁止 Double；
/// 「元」只在 UI 输入/展示层出现。
enum Money {

    /// 分 -> Decimal 元（用于图表数值等）
    static func yuan(fromCents cents: Int64) -> Decimal {
        Decimal(cents) / 100
    }

    /// 元（用户输入的 Decimal）-> 分，四舍五入到分
    static func cents(fromYuan value: Decimal) -> Int64 {
        let scaled = (value * 100).rounded(.toNearestOrEven)
        return Int64(NSDecimalNumber(decimal: scaled).int64Value)
    }

    /// 用户输入的金额字符串（"12" / "12.5" / "12.56"）-> 分；非法返回 nil
    /// 规则：仅数字与至多一个小数点，小数最多 2 位（超出截断），整数位 ≤ 9 位
    static func cents(fromString text: String) -> Int64? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        var yuanPart = ""
        var fenPart = ""
        var seenDot = false

        for ch in trimmed {
            if ch == "." {
                if seenDot { return nil }
                seenDot = true
            } else if ch.isNumber {
                if seenDot {
                    if fenPart.count < 2 { fenPart.append(ch) }
                } else {
                    if yuanPart.count >= 9 { return nil }
                    yuanPart.append(ch)
                }
            } else {
                return nil
            }
        }
        if yuanPart.isEmpty && fenPart.isEmpty { return nil }
        if yuanPart.isEmpty { yuanPart = "0" }

        let yuan = Int64(yuanPart) ?? 0
        var fen: Int64 = 0
        if fenPart.count == 1 { fen = (Int64(fenPart) ?? 0) * 10 }
        else if fenPart.count == 2 { fen = Int64(fenPart) ?? 0 }
        return yuan * 100 + fen
    }

    /// 分 -> 展示字符串，如 "1,234.56"；带符号可选
    static func string(fromCents cents: Int64, sign: Bool = false) -> String {
        let negative = cents < 0
        let absCents = abs(cents)
        let yuanDigits = String(absCents / 100)
        let grouped = group(yuanDigits)
        let fen = String(format: "%02lld", absCents % 100)
        var result = "\(grouped).\(fen)"
        if sign {
            result = (negative ? "-¥" : "+¥") + result
        } else {
            result = (negative ? "-¥" : "¥") + result
        }
        return result
    }

    /// 分 -> 纯数字输入回填串（无符号无分隔），如 "12.50"
    static func inputString(fromCents cents: Int64) -> String {
        let absCents = abs(cents)
        return String(format: "%lld.%02lld", absCents / 100, absCents % 100)
    }

    /// 千位分隔
    private static func group(_ digits: String) -> String {
        var chars = Array(digits)
        guard chars.count > 3 else { return digits }
        var out: [Character] = []
        while chars.count > 3 {
            let tail = chars.suffix(3)
            out.insert(contentsOf: tail, at: 0)
            out.insert(",", at: 0)
            chars.removeLast(3)
        }
        out.insert(contentsOf: chars, at: 0)
        return String(out)
    }
}
