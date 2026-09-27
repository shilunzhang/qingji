import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif
import UIKit

/// 语义增强抽取（文档 F-12/F-13 增强）：
/// iOS 26 + Apple Intelligence 设备 → 端侧大模型结构化抽取（免费/离线/隐私）
/// 其余情况 → 自动回退规则解析（findDate 标签优先 + parseAll）
/// 注意：FoundationModels 仅存在于 Xcode 26+ SDK，用 canImport 保护以兼容旧工具链
enum SmartExtractionService {

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }

    /// 图片 → 交易行（智能优先，规则兜底）
    static func extractRows(from image: UIImage) async -> [PaymentTextParser.ParsedPayment] {
        let text = await OCRService.recognizeText(in: image)
        guard !text.isEmpty else { return [] }

        #if canImport(FoundationModels)
        if #available(iOS 26, *), isAvailable {
            let smart = await extractWithModel(text: text, now: .now)
            if !smart.isEmpty {
                DiagLog.append("端侧模型抽取 \(smart.count) 笔")
                return smart
            }
            DiagLog.append("端侧模型无结果，回退规则解析")
        }
        #endif
        return PaymentTextParser.parseAll(text)
    }

    #if canImport(FoundationModels)
    @available(iOS 26, *)
    private static func extractWithModel(text: String, now: Date) async -> [PaymentTextParser.ParsedPayment] {
        let clipped = String(text.prefix(2500))
        do {
            let session = LanguageModelSession(instructions: Self.instructions(now: now))
            let response = try await session.respond(to: clipped, generating: SmartTransactionList.self)
            return response.content.transactions.compactMap { item in
                guard let cents = centsFrom(item.amount) else { return nil }
                return PaymentTextParser.ParsedPayment(amountCents: cents,
                                     date: parseTime(item.time, fallback: now),
                                     counterparty: item.merchant.isEmpty ? "支付" : item.merchant,
                                     kind: item.direction.lowercased() == "income" ? .income : .expense,
                                     note: item.note.isEmpty ? nil : item.note)
            }
        } catch {
            DiagLog.append("端侧模型抽取失败，回退规则：\(error.localizedDescription)")
            return []
        }
    }
    #endif

    private static func instructions(now: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return """
        你是个人记账助手。下面的文本来自支付或账单截图的 OCR 结果。截图里可能同时出现下单时间、付款时间等多个时间，务必以「付款时间/交易时间」为准。今天是 \(formatter.string(from: now))。请提取其中的交易记录：amount 取实付金额（数字，单位元）；direction 用 expense（支出）或 income（收入）；time 用页面上的付款/交易时间，格式 yyyy-MM-dd HH:mm；merchant 为商户或对方名称；note 用不超过 20 字的中文概括这笔消费用途（如「和同事的午餐」「打车回家」）。
        """
    }

    /// Double 元 → 分
    static func centsFrom(_ amount: Double) -> Int64? {
        let cents = Int64((amount * 100).rounded())
        return cents > 0 && cents < 99_999_999_00 ? cents : nil
    }

    /// 模型输出的时间字符串 → Date，解析失败回退 fallback
    static func parseTime(_ string: String, fallback: Date, calendar: Calendar = .current) -> Date {
        let formats = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm",
                       "yyyy/MM/dd HH:mm:ss", "yyyy/MM/dd HH:mm",
                       "yyyy年M月d日 HH:mm:ss", "yyyy年M月d日 HH:mm"]
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        for format in formats {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return fallback
    }
}

#if canImport(FoundationModels)
@available(iOS 26, *)
@Generable
struct SmartTransaction {
    @Guide(description: "实付金额，单位元，例如 45.60")
    var amount: Double
    @Guide(description: "方向：expense 表示支出，income 表示收入")
    var direction: String
    @Guide(description: "付款或交易时间，格式 yyyy-MM-dd HH:mm")
    var time: String
    @Guide(description: "商户名称或交易对方")
    var merchant: String
    @Guide(description: "不超过 20 字的中文用途说明")
    var note: String
}

@available(iOS 26, *)
@Generable
struct SmartTransactionList {
    @Guide(description: "截图中识别出的交易记录列表，单笔详情页只有一个元素")
    var transactions: [SmartTransaction]
}
#endif
