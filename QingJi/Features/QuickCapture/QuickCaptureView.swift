import SwiftUI
import SwiftData
import UIKit

/// 截图/拍照入账（文档 F-12/F-15）
/// v1.4.3：选择器直接内嵌为 sheet 内容（不再是 sheet 套 sheet）——
/// 取消（×/下滑）只关闭一次，杜绝中间空白卡片与串行关闭延迟；
/// 识别后原位切换为审核列表，全程同一个 sheet。
struct QuickCaptureView: View {
    enum Source { case album, camera }

    let source: Source

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    @State private var entries: [DraftEntry] = []
    @State private var processing = false
    @State private var savedCount = 0
    @State private var categoryTarget: CategoryTarget?
    @State private var pendingDuplicate: DuplicateMatch?
    @State private var confirmEntryID: DraftEntry.ID?
    @State private var duplicateBlockMessage: String?
    /// v1.4.3：picker 内嵌状态机
    @State private var picking = true        // true = 显示选择器（初始态）
    @State private var hasAttempted = false  // 已选过图（无论识别出几条）

    struct DraftEntry: Identifiable {
        let id = UUID()
        var kind: TxKind
        var amountText: String
        var date: Date
        var counterparty: String
        var note: String
        var channel: TxChannel?
        var category: Category?
        var account: Account?
        var warning: String
    }

    private struct CategoryTarget: Identifiable {
        let entryID: DraftEntry.ID
        var id: DraftEntry.ID { entryID }
    }

    var body: some View {
        Group {
            if processing {
                processingView
            } else if !entries.isEmpty {
                reviewList
            } else if savedCount > 0 {
                doneView
            } else if picking {
                pickerContent
            } else {
                fallbackView
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $categoryTarget) { target in
            CategoryPickerSheet(selected: nil, defaultKind: .expense) { picked in
                if let index = entries.firstIndex(where: { $0.id == target.entryID }) {
                    entries[index].category = picked
                }
            }
        }
        .modifier(DuplicateAlerts(
            pendingDuplicate: $pendingDuplicate,
            confirmEntryID: $confirmEntryID,
            blockMessage: $duplicateBlockMessage,
            onConfirm: { confirmAndSave() }
        ))
    }

    // MARK: - 内嵌选择器（sheet 内容本身）

    /// 相机不可用（模拟器/无摄像头）自动降级为相册选择器
    @ViewBuilder
    private var pickerContent: some View {
        if source == .camera && CameraPicker.isAvailable {
            CameraPicker(
                onImage: { image in
                    handleImages([image])
                },
                onCancel: {
                    // 取消：整个 sheet 一次关闭（无内层 sheet，无串行延迟）
                    dismiss()
                }
            )
            .ignoresSafeArea()
        } else {
            PhotoLibraryPicker(maxCount: 5) { images in
                if images.isEmpty {
                    // × 取消 / 未选任何图：一次关闭
                    dismiss()
                } else {
                    handleImages(images)
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private var processingView: some View {
        VStack(spacing: 12) {
            ProgressView().scaleEffect(1.5)
            Text("正在识别截图内容…").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }

    private var reviewList: some View {
        List {
            ForEach($entries) { $entry in
                entryCard($entry)
            }
            if savedCount > 0 {
                Section {
                    Label("已保存 \(savedCount) 笔", systemImage: "checkmark.seal")
                        .foregroundStyle(Theme.income)
                }
            }
            if entries.isEmpty && savedCount > 0 {
                Section {
                    Button("完成") { dismiss() }.frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func entryCard(_ entry: Binding<DraftEntry>) -> some View {
        Section {
            TextField("金额（元）", text: entry.amountText)
                .keyboardType(.decimalPad)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    discardSwipe(entry.wrappedValue.id)
                }
            DatePicker("时间", selection: entry.date)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    discardSwipe(entry.wrappedValue.id)
                }
            TextField("收款方/商户", text: entry.counterparty)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    discardSwipe(entry.wrappedValue.id)
                }
            HStack {
                Text("账户")
                Spacer()
                Menu(entry.wrappedValue.account?.name ?? "请选择") {
                    ForEach(activeAccounts) { account in
                        Button(account.name) { entry.wrappedValue.account = account }
                    }
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                discardSwipe(entry.wrappedValue.id)
            }
            HStack {
                Text("分类")
                Spacer()
                Button(entry.wrappedValue.category?.name ?? "未分类") {
                    categoryTarget = CategoryTarget(entryID: entry.wrappedValue.id)
                }
                .foregroundStyle(.secondary)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                discardSwipe(entry.wrappedValue.id)
            }
            if let dup = duplicateHint(for: entry.wrappedValue) {
                Label("疑似与已有账目重复：\(dup.summary)", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(Theme.alert)
            }
            if !entry.wrappedValue.warning.isEmpty {
                Label(entry.wrappedValue.warning, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(Theme.alert)
            }
            Button {
                save(entry.wrappedValue)
            } label: {
                Text("确认入账").frame(maxWidth: .infinity).fontWeight(.semibold)
            }
            .disabled(!canSave(entry.wrappedValue))
        }
    }

    private var doneView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle").font(.system(size: 56)).foregroundStyle(Theme.income)
            Text("已保存 \(savedCount) 笔").font(.title3.weight(.semibold))
            Button("完成") { dismiss() }.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: - 空态兜底

    /// 选过图但识别 0 条：给出出口，杜绝死页
    @ViewBuilder
    private var fallbackView: some View {
        VStack(spacing: 14) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("未识别到账单记录").font(.headline)
            Text("换一张支付成功页截图试试，或改用手动记账")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("重新选择") {
                hasAttempted = false
                picking = true
            }
            .buttonStyle(.borderedProminent)
            Button("关闭") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: - v1.4.2 重复提示与左滑丢弃

    /// 左滑丢弃候选条目（从待确认列表移除，不入账）
    @ViewBuilder
    private func discardSwipe(_ id: DraftEntry.ID) -> some View {
        Button(role: .destructive) {
            withAnimation { entries.removeAll { $0.id == id } }
        } label: {
            Label("丢弃", systemImage: "trash")
        }
    }

    /// F-14 预检提示：与历史账目同向同额且时间差 ≤ 窗口 → 审核卡片上黄字提醒。
    /// 保存时仍会走完整闸门（弹窗确认/阻止），这里只是提前告知
    private func duplicateHint(for entry: DraftEntry) -> DuplicateMatch? {
        guard DuplicateGuard.sensitivity != .off else { return nil }
        guard let cents = Money.cents(fromString: entry.amountText), cents > 0 else { return nil }
        return DuplicateGuard.findDuplicate(of: entry.kind, amountCents: cents,
                                            date: entry.date, in: history)
    }

    // MARK: - 数据与保存

    private var activeAccounts: [Account] {
        accounts.filter { !$0.isArchived }
    }

    private var history: [Transaction] {
        (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
    }

    private func resolveAccount(for entry: DraftEntry) -> Account? {
        let channelAccount = entry.channel?.accountKind.flatMap { kind in
            accounts.first { $0.kind == kind && !$0.isArchived }
        }
        return entry.account ?? channelAccount ?? accounts.first(where: { !$0.isArchived })
    }

    private func canSave(_ entry: DraftEntry) -> Bool {
        guard let cents = Money.cents(fromString: entry.amountText), cents > 0 else { return false }
        return entry.account != nil || !activeAccounts.isEmpty
    }

    private func save(_ entry: DraftEntry) {
        guard let cents = Money.cents(fromString: entry.amountText), cents > 0 else { return }
        guard let account = resolveAccount(for: entry) else { return }
        let match = DuplicateGuard.findDuplicate(of: entry.kind, amountCents: cents, date: entry.date, in: history)
        switch DuplicateGuard.manualDecision(for: match) {
        case .allow: commit(entry, cents: cents, account: account)
        case .confirm(let d): pendingDuplicate = d; confirmEntryID = entry.id
        case .block(let d): duplicateBlockMessage = "已存在 \(d.summary)。"
        }
    }

    private func confirmAndSave() {
        guard let id = confirmEntryID,
              let index = entries.firstIndex(where: { $0.id == id }),
              let cents = Money.cents(fromString: entries[index].amountText), cents > 0,
              let account = resolveAccount(for: entries[index]) else { return }
        commit(entries[index], cents: cents, account: account)
    }

    private func commit(_ entry: DraftEntry, cents: Int64, account: Account) {
        var entry = entry
        if entry.category == nil, !entry.counterparty.isEmpty {
            entry.category = CategoryPredictor.category(forMerchant: entry.counterparty, in: history)
        }
        let noteText = entry.note.isEmpty ? entry.counterparty : entry.note
        let tx = Transaction(kind: entry.kind, amountCents: cents, date: entry.date,
                             account: account, category: entry.category, note: noteText, channel: entry.channel)
        context.insert(tx)
        try? context.save()
        AutoPostStore.shared.recordPosted(txID: tx.id, kind: entry.kind,
                                          amountCents: cents, date: entry.date, note: noteText)
        savedCount += 1
        entries.removeAll { $0.id == entry.id }
    }

    private func handleImages(_ images: [UIImage]) {
        processing = true
        picking = false
        Task { @MainActor in
            var drafts: [DraftEntry] = []
            for image in images {
                for row in await SmartExtractionService.extractRows(from: image) {
                    drafts.append(makeEntry(from: row))
                }
            }
            entries.append(contentsOf: drafts)
            hasAttempted = true
            processing = false
        }
    }

    private func makeEntry(from row: PaymentTextParser.ParsedPayment) -> DraftEntry {
        var warning = ""
        if (row.amountCents ?? 0) <= 0 { warning = "未识别出金额，请手动补填" }
        return DraftEntry(kind: row.kind ?? .expense,
                          amountText: row.amountCents.map { Money.inputString(fromCents: $0) } ?? "",
                          date: row.date ?? Date(),
                          counterparty: row.counterparty ?? "",
                          note: row.note ?? "",
                          channel: row.channel, category: nil,
                          account: activeAccounts.first, warning: warning)
    }
}
