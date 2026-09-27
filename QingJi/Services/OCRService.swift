import Foundation
import UIKit
import Vision

/// OCR 文本识别（文档 F-09）：Vision 中文识别，结果回主线程
enum OCRService {

    enum OCRError: LocalizedError {
        case invalidImage
        var errorDescription: String? { "图片无法读取" }
    }

    static func recognizeText(in image: UIImage,
                              completion: @escaping (Result<String, Error>) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(.failure(OCRError.invalidImage))
            return
        }

        let finish: (Result<String, Error>) -> Void = makeOnce(completion)

        let request = VNRecognizeTextRequest { request, error in
            if let error {
                finish(.failure(error))
                return
            }
            let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
            let text = observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
            finish(.success(text))
        }
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans"]
        request.usesLanguageCorrection = true

        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                finish(.failure(error))
            }
        }
    }

    /// 保证 completion 只被调用一次（请求回调与 perform 异常可能双路径触发）
    private static func makeOnce(_ completion: @escaping (Result<String, Error>) -> Void) -> (Result<String, Error>) -> Void {
        let lock = NSLock()
        var finished = false
        return { result in
            lock.lock()
            guard !finished else { lock.unlock(); return }
            finished = true
            lock.unlock()
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// async 版本（App Intent / 相册扫描使用）
    static func recognizeText(in image: UIImage) async -> String {
        await withCheckedContinuation { continuation in
            recognizeText(in: image) { result in
                switch result {
                case .success(let text):
                    continuation.resume(returning: text)
                case .failure:
                    continuation.resume(returning: "")
                }
            }
        }
    }
}

/// 支付文本解析（文档 F-09）：OCR 结果 -> 金额/时间/收款方
/// 纯函数，可单测。规则优先「带标签金额行」，其次取候选中最大值（支付成功页实付金额最大）。
enum PaymentTextParser {

    struct ParsedPayment {
        var amountCents: Int64?
        var date: Date?
        var counterparty: String?
        /// 多行解析时的收支方向；单笔解析为 nil（默认按支出处理）
        var kind: TxKind? = nil
        /// 语义化备注（端侧大模型生成，规则解析为 nil）
        var note: String? = nil
    }

    private static let labeledAmountPattern =
        #"(?:实付金额|付款金额|支付金额|实付款|支付总额|订单金额|共支付|金额)[^0-9¥￥]{0,8}[¥￥]?\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)"#
    private static let currencyAmountPattern = #"[¥￥]\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)"#
    private static let yuanAmountPattern = #"([0-9][0-9,]*(?:\.[0-9]{1,2})?)\s*元"#
    private static let datePattern =
        #"([0-9]{4})[-/年]([0-9]{1,2})[-/月]([0-9]{1,2})日?\s+([0-9]{1,2}):([0-9]{2})(?::([0-9]{2}))?"#
    private static let counterpartyPattern =
        #"(?:收款方|付款给|收款商户|商户全称|商户名称|对方名称|对方)[:：]?\s*(.+)"#

    static func parse(_ text: String, calendar: Calendar = .current) -> ParsedPayment {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var result = ParsedPayment()
        result.amountCents = findAmount(in: lines)
        result.date = findDate(in: text, calendar: calendar)
        result.counterparty = findCounterparty(in: lines)
        return result
    }

    /// 多笔解析（文档 F-13 增强）：账单列表页一行一笔，日期行为分组头；
    /// 单笔详情页自动回落到 parse()。行格式：「瑞幸咖啡 -¥19.90」「工资到账 +¥3000.00」
    static func parseAll(_ text: String, calendar: Calendar = .current) -> [ParsedPayment] {
        let rows = extractSignedRows(text, calendar: calendar)
        if rows.count >= 2 { return rows }

        let single = parse(text, calendar: calendar)
        if let cents = single.amountCents {
            var result = single
            if result.kind == nil { result.kind = .expense }
            return [result]
        }
        return rows
    }

    /// 逐行提取带 +/- 方向的金额行
    static func extractSignedRows(_ text: String, calendar: Calendar = .current) -> [ParsedPayment] {
        let skipKeywords = ["合计", "余额", "退款", "手续费"]
        let signedPattern = "([+-])\\s*[¥￥]?\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)"
        guard let signedRegex = try? NSRegularExpression(pattern: signedPattern) else { return [] }

        var results: [ParsedPayment] = []
        var lastDate: Date?

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            // 日期分组头（如「9月26日」「2026-09-26」）→ 记录并跳过
            if let headerDate = dateHeader(line, calendar: calendar) {
                lastDate = headerDate
                continue
            }
            if skipKeywords.contains(where: line.contains) { continue }

            let ns = line as NSString
            let range = NSRange(location: 0, length: ns.length)
            let matches = signedRegex.matches(in: line, range: range)
            guard matches.count == 1 else { continue } // 一行只认一笔，避免误拆

            let match = matches[0]
            guard match.range(at: 1).location != NSNotFound,
                  match.range(at: 2).location != NSNotFound else { continue }
            let sign = ns.substring(with: match.range(at: 1))
            let rawAmount = ns.substring(with: match.range(at: 2))
            let cleaned = rawAmount.filter { $0.isNumber || $0 == "." }
            guard let cents = Money.cents(fromString: cleaned), cents > 0 else { continue }

            var name = ns.replacingCharacters(in: match.range, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            name = name.trimmingCharacters(in: CharacterSet(charactersIn: "+-·¥￥,:："))
                .trimmingCharacters(in: .whitespaces)
            if name.count < 2 { name = "账单交易" }

            results.append(ParsedPayment(amountCents: cents,
                                         date: lastDate,
                                         counterparty: name,
                                         kind: sign == "+" ? .income : .expense))
        }
        return results
    }

    /// 日期分组头：「9月26日」「2026年9月26日」「2026-09-26」
    private static func dateHeader(_ line: String, calendar: Calendar) -> Date? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let ns = trimmed as NSString
        let range = NSRange(location: 0, length: ns.length)

        let cnPattern = "^(?:([0-9]{4})年)?([0-9]{1,2})月([0-9]{1,2})日?$"
        if let regex = try? NSRegularExpression(pattern: cnPattern),
           let match = regex.firstMatch(in: trimmed, range: range) {
            var comps = DateComponents()
            let yearRange = match.range(at: 1)
            comps.year = yearRange.location != NSNotFound
                ? Int(ns.substring(with: yearRange))
                : calendar.component(.year, from: .now)
            comps.month = Int(ns.substring(with: match.range(at: 2))) ?? 1
            comps.day = Int(ns.substring(with: match.range(at: 3))) ?? 1
            comps.hour = 12
            return calendar.date(from: comps)
        }

        let isoPattern = "^([0-9]{4})[-/]([0-9]{1,2})[-/]([0-9]{1,2})$"
        if let regex = try? NSRegularExpression(pattern: isoPattern),
           let match = regex.firstMatch(in: trimmed, range: range) {
            var comps = DateComponents()
            comps.year = Int(ns.substring(with: match.range(at: 1)))
            comps.month = Int(ns.substring(with: match.range(at: 2)))
            comps.day = Int(ns.substring(with: match.range(at: 3)))
            comps.hour = 12
            return calendar.date(from: comps)
        }
        return nil
    }

    /// 支付成功页特征判定（文档 F-12/F-13）：含支付类关键词 + 能解析出金额才认定为支付页，
    /// 避免把聊天/文章里的零散数字误判为消费
    static func looksLikePaymentPage(_ text: String) -> Bool {
        let keywords = ["支付成功", "付款成功", "收款成功", "交易成功", "到账", "付款金额",
                        "支付金额", "实付", "已支付", "收款金额", "入账", "收银台"]
        guard keywords.contains(where: { text.contains($0) }) else { return false }
        return parse(text).amountCents != nil
    }

    // MARK: - 金额

    private static func findAmount(in lines: [String]) -> Int64? {
        // 排除优惠/退款类行，避免误取折扣金额
        let noise = ["退款", "优惠", "折扣", "立减", "红包", "抵扣"]
        let labeledLines = lines.filter { line in
            !noise.contains { line.contains($0) }
                && firstMatchRange(pattern: labeledAmountPattern, in: line) != nil
        }
        if let line = labeledLines.first, let cents = maxAmount(in: line, pattern: labeledAmountPattern) {
            return sanitize(cents)
        }

        var candidates: [Int64] = []
        for line in lines {
            candidates.append(contentsOf: amounts(in: line, pattern: currencyAmountPattern))
            candidates.append(contentsOf: amounts(in: line, pattern: yuanAmountPattern))
        }
        return candidates.map(sanitize).compactMap { $0 }.max()
    }

    private static func sanitize(_ cents: Int64) -> Int64? {
        cents > 0 && cents < 99_999_999_00 ? cents : nil
    }

    private static func amounts(in text: String, pattern: String) -> [Int64] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        return matches.compactMap { match in
            guard match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound else { return nil }
            let raw = ns.substring(with: match.range(at: 1))
            let cleaned = raw.filter { $0.isNumber || $0 == "." }
            return Money.cents(fromString: cleaned)
        }
    }

    private static func maxAmount(in text: String, pattern: String) -> Int64? {
        amounts(in: text, pattern: pattern).max()
    }

    private static func firstMatchRange(pattern: String, in text: String) -> NSRange? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        return regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length))?.range
    }

    // MARK: - 日期

    static func findDate(in text: String, calendar: Calendar = .current) -> Date? {
        let timePart = #"(?:[0-9]{4}[-/年])?[0-9]{1,2}[-/月][0-9]{1,2}日?\s*[0-9]{1,2}:[0-9]{2}(?::[0-9]{2})?"#
        // 第一优先：付款/交易/到账等确定性时间标签（正则交替按文本位置取最早，
        // 因此「下单时间」必须单独放第二轮，否则会抢在前面的下单时间）
        let strongPattern = #"(?:交易时间|付款时间|支付时间|到账时间|收款时间|成功时间)\s*[:：]?\s*("# + timePart + #")"#
        if let date = dateFromCapture(strongPattern, groupIndex: 1, text: text, calendar: calendar) {
            return date
        }
        // 第二优先：下单时间/订单时间/日期
        let weakPattern = #"(?:下单时间|订单时间|日期)\s*[:：]?\s*("# + timePart + #")"#
        if let date = dateFromCapture(weakPattern, groupIndex: 1, text: text, calendar: calendar) {
            return date
        }
        return dateFromCapture(datePattern, groupIndex: 0, text: text, calendar: calendar)
    }

    private static func dateFromCapture(_ pattern: String, groupIndex: Int, text: String, calendar: Calendar) -> Date? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let groupRange = groupIndex == 0 ? match.range : match.range(at: groupIndex)
        guard groupRange.location != NSNotFound else { return nil }
        return componentsDate(from: ns.substring(with: groupRange), calendar: calendar)
    }

    /// 从任意日期片段抽取年月日时分（年份可选，缺省按当前年补齐）
    private static func componentsDate(from string: String, calendar: Calendar) -> Date? {
        let pattern = #"(?:([0-9]{4})[-/年])?([0-9]{1,2})[-/月]([0-9]{1,2})日?\s*([0-9]{1,2}):([0-9]{2})(?::([0-9]{2}))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = string as NSString
        guard let match = regex.firstMatch(in: string, range: NSRange(location: 0, length: ns.length)) else { return nil }

        func int(_ index: Int) -> Int {
            let r = match.range(at: index)
            guard r.location != NSNotFound else { return 0 }
            return Int(ns.substring(with: r)) ?? 0
        }

        var comps = DateComponents()
        comps.year = int(1)
        if comps.year == 0 { comps.year = calendar.component(.year, from: .now) }
        comps.month = int(2)
        comps.day = int(3)
        comps.hour = int(4)
        comps.minute = int(5)
        comps.second = match.numberOfRanges > 6 && match.range(at: 6).location != NSNotFound ? int(6) : 0
        return calendar.date(from: comps)
    }

    // MARK: - 收款方

    private static func findCounterparty(in lines: [String]) -> String? {
        for line in lines {
            guard let range = firstMatchRange(pattern: counterpartyPattern, in: line) else { continue }
            let ns = line as NSString
            // 取整个捕获组：重新用正则提取 group 1
            if let regex = try? NSRegularExpression(pattern: counterpartyPattern),
               let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
               match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound {
                var candidate = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
                // 去掉尾随金额
                if let regex2 = try? NSRegularExpression(pattern: currencyAmountPattern) {
                    candidate = regex2.stringByReplacingMatches(
                        in: candidate,
                        range: NSRange(location: 0, length: (candidate as NSString).length),
                        withTemplate: "").trimmingCharacters(in: .whitespaces)
                }
                if !candidate.isEmpty { return candidate }
            }
        }
        return nil
    }
}
