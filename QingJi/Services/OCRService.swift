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
        guard let regex = try? NSRegularExpression(pattern: datePattern) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 6 else { return nil }

        func int(_ index: Int) -> Int {
            let range = match.range(at: index)
            guard range.location != NSNotFound else { return 0 }
            return Int(ns.substring(with: range)) ?? 0
        }

        var comps = DateComponents()
        comps.year = int(1)
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
