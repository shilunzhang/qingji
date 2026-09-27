import AppIntents
import SwiftData
import UIKit

/// 「截图入账」App Intent（文档 F-12）
/// 推荐的快捷指令自动化：关闭支付宝/微信 → 获取最新截屏 → 本意图 → 删除照片
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

        // 语义增强抽取：端侧大模型优先，规则解析兜底；一张截图可含多笔（文档 F-12/F-13）
        let rows = await SmartExtractionService.extractRows(from: image)
        guard !rows.isEmpty else {
            DiagLog.append("未识别到交易，静默跳过")
            return .result(dialog: "未识别到支付信息，已忽略")
        }

        var confirmedCount = 0
        var confirmedTotal: Int64 = 0
        var skippedCount = 0
        var firstSummary = ""

        for (index, row) in rows.enumerated() {
            guard let cents = row.amountCents, cents > 0 else { continue }
            let merchant: String
            if let name = row.counterparty, !name.isEmpty {
                merchant = name
            } else {
                merchant = "支付"
            }
            let tradeDate = row.date ?? .now

            // 同页指纹：加入行序号，同页多笔互不误伤（AC3，F-14 第 2 道）
            let fingerprint = ScreenshotFingerprintStore.fingerprint(
                amountCents: cents,
                pageDate: row.date,
                merchant: "\(merchant)#\(index)")
            guard !ScreenshotFingerprintStore.contains(fingerprint) else {
                DiagLog.append("指纹命中，跳过第 \(index + 1) 笔")
                continue
            }
            ScreenshotFingerprintStore.insert(fingerprint)

            // F-14 自动闸门
            let context = ModelContext(AppDatabase.shared)
            let history = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
            let match = DuplicateGuard.findDuplicate(of: row.kind ?? .expense,
                                                     amountCents: cents,
                                                     date: tradeDate,
                                                     in: history)
            if case .skip(let duplicated) = DuplicateGuard.autoDecision(for: match) {
                skippedCount += 1
                AutoPostStore.shared.recordSkipped(kind: row.kind ?? .expense, amountCents: cents,
                                                   date: tradeDate, note: merchant)
                DiagLog.append("防重闸门跳过：\(duplicated.summary)")
                continue
            }

            let note = row.note?.isEmpty == false ? row.note! : merchant

            if CaptureSettings.autoSave {
                CaptureNotificationHandler.postDirectly(amountCents: cents, date: tradeDate, note: note)
                confirmedCount += 1
                confirmedTotal += cents
                DiagLog.append("静默自动入账 \(Money.string(fromCents: cents))·\(merchant)")
            } else {
                // 确认式：暂存 + 通知卡
                let capture = PendingCaptureStore.shared.add(amountCents: cents, date: tradeDate, note: note)
                let delivered = try await CaptureNotificationHandler.postConfirmNotification(capture)
                if delivered {
                    confirmedCount += 1
                    confirmedTotal += cents
                    DiagLog.append("确认卡已发送 \(Money.string(fromCents: cents))")
                } else {
                    // 通知权限不可用 → 降级直接入账，避免漏账
                    CaptureNotificationHandler.postDirectly(amountCents: cents, date: tradeDate, note: note)
                    confirmedCount += 1
                    confirmedTotal += cents
                    DiagLog.append("通知权限不可用，降级直接入账 \(Money.string(fromCents: cents))")
                }
            }
            if firstSummary.isEmpty {
                firstSummary = "\(Money.string(fromCents: cents))·\(merchant)"
            }
        }

        if confirmedCount == 0 && skippedCount == 0 {
            return .result(dialog: "未识别到支付信息，已忽略")
        }
        if confirmedCount == 0 {
            return .result(dialog: "疑似重复，已跳过 \(skippedCount) 笔")
        }
        if confirmedCount == 1 {
            return .result(dialog: "检测到 \(firstSummary)，请在通知中点「入账」")
        }
        return .result(dialog: "检测到 \(confirmedCount) 笔支付，共 \(Money.string(fromCents: confirmedTotal))，请在通知中逐笔确认")
    }
}
