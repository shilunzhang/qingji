import SwiftUI
import SwiftData

/// 相册扫描待确认草稿（F-13）。一张截图可解析出多笔（id = assetID#序号）
struct AlbumScanDraft: Identifiable {
    let id: String
    /// 来源截图的 asset localIdentifier（全部草稿处理完才标记已处理）
    let assetID: String
    var kind: TxKind
    var amountText: String
    var date: Date
    var counterparty: String
    /// 语义化备注（端侧模型生成，可编辑）
    var note: String
    var category: Category?
    var account: Account?
    var warning: String
}

/// 扫描模型：增量扫描 → OCR → 多笔解析 → 草稿；入账时逐条过 F-14 自动闸门
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
        var skippedNonPayment = 0
        let processed = AlbumScanStore.processedIDs()

        for item in assets {
            guard !processed.contains(item.assetID) else { continue }

            let parsed = await recognize(item.image)
            guard !parsed.isEmpty else {
                // 非支付/账单页 → 登记已处理，静默跳过
                AlbumScanStore.markProcessed(item.assetID)
                skippedNonPayment += 1
                continue
            }

            for (index, row) in parsed.enumerated() {
                let fingerprint = ScreenshotFingerprintStore.fingerprint(amountCents: row.amountCents ?? 0,
                                                                         pageDate: row.date ?? item.creationDate,
                                                                         merchant: row.counterparty ?? "")
                guard !ScreenshotFingerprintStore.contains(fingerprint) else { continue }
                ScreenshotFingerprintStore.insert(fingerprint)

                newDrafts.append(AlbumScanDraft(id: "\(item.assetID)#\(index)",
                                                assetID: item.assetID,
                                                kind: row.kind ?? .expense,
                                                amountText: Money.inputString(fromCents: row.amountCents ?? 0),
                                                date: row.date ?? item.creationDate,
                                                counterparty: row.counterparty ?? "",
                                                note: row.note ?? "",
                                                category: nil,
                                                account: nil,
                                                warning: ""))
            }
        }

        AlbumScanStore.setLastScanDate(.now)

        let existingIDs = Set(drafts.map(\.id))
        drafts.insert(contentsOf: newDrafts.filter { !existingIDs.contains($0.id) }, at: 0)

        if assets.isEmpty {
            lastScanText = "没有读取到新的屏幕快照。若照片权限为「有限访问」，请在系统设置中改为允许所有照片"
        } else {
            lastScanText = "扫描 \(assets.count) 张快照：新增 \(newDrafts.count) 笔待确认，\(skippedNonPayment) 张非账单页已跳过"
        }
    }

    /// 入账：过 F-14 自动决策闸门（疑似重复 → 记日志跳过）
    func commit(_ draft: AlbumScanDraft, context: ModelContext, fallbackAccount: Account?) {
        guard let cents = Money.cents(fromString: draft.amountText), cents > 0,
              let account = draft.account ?? fallbackAccount else { return }

        let history = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        let match = DuplicateGuard.findDuplicate(of: draft.kind,
                                                 amountCents: cents,
                                                 date: draft.date,
                                                 in: history)
        // 备注：优先语义化说明，回退商户名
        let noteText = draft.note.isEmpty ? draft.counterparty : draft.note

        switch DuplicateGuard.autoDecision(for: match) {
        case .post:
            let tx = Transaction(kind: draft.kind,
                                 amountCents: cents,
                                 date: draft.date,
                                 account: account,
                                 category: draft.category,
                                 note: noteText,
                                 source: .album)
            context.insert(tx)
            try? context.save()
            AutoPostStore.shared.recordPosted(txID: tx.id, kind: draft.kind,
                                              amountCents: cents, date: draft.date,
                                              note: noteText)
        case .skip(let duplicated):
            AutoPostStore.shared.recordSkipped(kind: draft.kind, amountCents: cents,
                                               date: draft.date,
                                               note: draft.counterparty.isEmpty
                                                   ? "疑似重复：\(duplicated.summary)"
                                                   : noteText)
        }
        finish(draft)
    }

    /// 忽略：登记已处理，不再弹出
    func ignore(_ draft: AlbumScanDraft) {
        finish(draft)
    }

    /// 同一截图的多笔草稿全部处理完，才把截图标记为已处理
    private func finish(_ draft: AlbumScanDraft) {
        let assetID = draft.assetID
        drafts.removeAll { $0.id == draft.id }
        if !drafts.contains(where: { $0.assetID == assetID }) {
            AlbumScanStore.markProcessed(assetID)
        }
    }

    private func recognize(_ image: UIImage) async -> [PaymentTextParser.ParsedPayment] {
        // 端侧大模型优先，规则解析兜底（文档 F-12/F-13 语义增强）
        await SmartExtractionService.extractRows(from: image)
    }
}
