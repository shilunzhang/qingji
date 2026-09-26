import SwiftUI
import SwiftData

/// 相册扫描待确认草稿（F-13）
struct AlbumScanDraft: Identifiable {
    /// 相册 asset localIdentifier
    let id: String
    var amountText: String
    var date: Date
    var counterparty: String
    var category: Category?
    var account: Account?
    var warning: String
}

/// 扫描模型：增量扫描 → OCR → 支付页判定 → 草稿；入账时过 F-14 自动闸门
@MainActor
final class AlbumScanModel: ObservableObject {

    static let shared = AlbumScanModel()

    @Published var drafts: [AlbumScanDraft] = []
    @Published var isScanning = false
    @Published var lastScanText: String?

    /// App 启动时调用：已授权才静默扫描
    func scanIfAuthorized() async {
        guard PhotoScanService.isAuthorized else { return }
        await scan()
    }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        let since = AlbumScanStore.lastScanDate()
        let assets = PhotoScanService.fetchNewScreenshots(after: since, limit: 10)

        var newDrafts: [AlbumScanDraft] = []
        let processed = AlbumScanStore.processedIDs()

        for item in assets {
            guard !processed.contains(item.assetID) else { continue }

            let parsed = await recognize(item.image)

            // 非支付页（识别不出金额）→ 登记已处理，静默跳过（AC：零打扰）
            guard let cents = parsed.amountCents else {
                AlbumScanStore.markProcessed(item.assetID)
                continue
            }

            // 同一支付页指纹已见过 → 静默跳过（F-14 第 2 道）
            let fingerprint = ScreenshotFingerprintStore.fingerprint(amountCents: cents,
                                                                     pageDate: parsed.date,
                                                                     merchant: parsed.counterparty ?? "")
            guard !ScreenshotFingerprintStore.contains(fingerprint) else {
                AlbumScanStore.markProcessed(item.assetID)
                continue
            }
            ScreenshotFingerprintStore.insert(fingerprint)

            newDrafts.append(AlbumScanDraft(id: item.assetID,
                                            amountText: Money.inputString(fromCents: cents),
                                            date: parsed.date ?? item.creationDate,
                                            counterparty: parsed.counterparty ?? "",
                                            category: nil,
                                            account: nil,
                                            warning: ""))
        }

        AlbumScanStore.setLastScanDate(.now)

        let existingIDs = Set(drafts.map(\.id))
        drafts.insert(contentsOf: newDrafts.filter { !existingIDs.contains($0.id) }, at: 0)

        lastScanText = newDrafts.isEmpty ? "没有发现新的支付截图" : "发现 \(newDrafts.count) 笔待确认"
    }

    /// 入账：过 F-14 自动决策闸门（疑似重复 → 记日志跳过）
    func commit(_ draft: AlbumScanDraft, context: ModelContext, fallbackAccount: Account?) {
        guard let cents = Money.cents(fromString: draft.amountText), cents > 0,
              let account = draft.account ?? fallbackAccount else { return }

        let history = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        let match = DuplicateGuard.findDuplicate(of: .expense,
                                                 amountCents: cents,
                                                 date: draft.date,
                                                 in: history)
        switch DuplicateGuard.autoDecision(for: match) {
        case .post:
            let tx = Transaction(kind: .expense,
                                 amountCents: cents,
                                 date: draft.date,
                                 account: account,
                                 category: draft.category,
                                 note: draft.counterparty,
                                 source: .album)
            context.insert(tx)
            try? context.save()
            AutoPostStore.shared.recordPosted(txID: tx.id, kind: .expense,
                                              amountCents: cents, date: draft.date,
                                              note: draft.counterparty)
        case .skip(let duplicated):
            AutoPostStore.shared.recordSkipped(kind: .expense, amountCents: cents,
                                               date: draft.date,
                                               note: draft.counterparty.isEmpty
                                                   ? "疑似重复：\(duplicated.summary)"
                                                   : draft.counterparty)
        }
        finish(draft)
    }

    /// 忽略：登记已处理，不再弹出
    func ignore(_ draft: AlbumScanDraft) {
        finish(draft)
    }

    private func finish(_ draft: AlbumScanDraft) {
        AlbumScanStore.markProcessed(draft.id)
        drafts.removeAll { $0.id == draft.id }
    }

    private func recognize(_ image: UIImage) async -> PaymentTextParser.ParsedPayment {
        let rawData = image.jpegData(compressionQuality: 0.9) ?? Data()
        guard let compressed = AddTransactionView.compress(imageData: rawData, maxDimension: 1600),
              let target = UIImage(data: compressed) else {
            return PaymentTextParser.ParsedPayment()
        }
        return await withCheckedContinuation { continuation in
            OCRService.recognizeText(in: target) { result in
                switch result {
                case .success(let text):
                    continuation.resume(returning: PaymentTextParser.parse(text))
                case .failure:
                    continuation.resume(returning: PaymentTextParser.ParsedPayment())
                }
            }
        }
    }
}
