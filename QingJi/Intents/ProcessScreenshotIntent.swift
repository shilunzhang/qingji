import AppIntents
import SwiftData
import UIKit

/// 「截图入账」App Intent（文档 F-12）
/// 推荐的快捷指令自动化：关闭支付宝/微信 → 拍摄屏幕快照 → 本意图 → 删除照片
struct ProcessScreenshotIntent: AppIntent {

    static var title: LocalizedStringResource = "截图入账"
    static var description: IntentDescription {
        IntentDescription("识别支付截图，弹通知确认入账；开启「静默自动入账」后可直接入账。")
    }
    static var openAppWhenRun: Bool = false

    @Parameter(title: "截图") var screenshot: IntentFile

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        DiagLog.append("Intent 触发")
        let data = try await screenshot.data
        guard let image = UIImage(data: data) else {
            DiagLog.append("截图数据无法读取")
            return .result(dialog: "截图无法读取")
        }

        // 本地 OCR（文档 F-09 识别引擎复用）
        let text = await OCRService.recognizeText(in: image)
        DiagLog.append("OCR 完成，识别 \(text.count) 字符")
        let parsed = PaymentTextParser.parse(text)

        // 非支付页 → 完全静默（AC2）
        guard PaymentTextParser.looksLikePaymentPage(text),
              let cents = parsed.amountCents else {
            DiagLog.append("非支付页，静默跳过")
            return .result(dialog: "未识别到支付信息，已忽略")
        }

        // 同一支付页指纹（AC3，F-14 第 2 道）
        let fingerprint = ScreenshotFingerprintStore.fingerprint(amountCents: cents,
                                                                 pageDate: parsed.date,
                                                                 merchant: parsed.counterparty ?? "")
        guard !ScreenshotFingerprintStore.contains(fingerprint) else {
            DiagLog.append("指纹命中，跳过（同页重复）")
            return .result(dialog: "该支付页已处理过，已跳过")
        }
        ScreenshotFingerprintStore.insert(fingerprint)

        let amountText = Money.string(fromCents: cents)
        let merchant = parsed.counterparty ?? "支付"
        let tradeDate = parsed.date ?? .now
        DiagLog.append("识别成功 \(amountText) · \(merchant)")

        // F-14 自动闸门
        let context = ModelContext(AppDatabase.shared)
        let history = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        let match = DuplicateGuard.findDuplicate(of: .expense,
                                                 amountCents: cents,
                                                 date: tradeDate,
                                                 in: history)
        if case .skip(let duplicated) = DuplicateGuard.autoDecision(for: match) {
            AutoPostStore.shared.recordSkipped(kind: .expense, amountCents: cents,
                                               date: tradeDate, note: merchant)
            DiagLog.append("防重闸门跳过：\(duplicated.summary)")
            return .result(dialog: "疑似重复，已跳过（\(duplicated.summary)）")
        }

        if CaptureSettings.autoSave {
            // 静默自动入账
            CaptureNotificationHandler.postDirectly(amountCents: cents, date: tradeDate, note: merchant)
            DiagLog.append("静默自动入账 \(amountText)")
            return .result(dialog: "已自动入账 \(amountText)·\(merchant)")
        }

        // 确认式：暂存 + 通知卡
        let capture = PendingCaptureStore.shared.add(amountCents: cents, date: tradeDate, note: merchant)
        let delivered = try await CaptureNotificationHandler.postConfirmNotification(capture)
        if delivered {
            DiagLog.append("确认卡已发送 \(amountText)")
            return .result(dialog: "检测到 \(amountText)·\(merchant)，请在通知中点「入账」")
        }
        // 通知权限不可用 → 降级为直接入账，避免漏账
        CaptureNotificationHandler.postDirectly(amountCents: cents, date: tradeDate, note: merchant)
        DiagLog.append("通知权限不可用，降级直接入账 \(amountText)")
        return .result(dialog: "通知权限未开启，已直接入账 \(amountText)")
    }
}
