import SwiftUI
import SwiftData
import UIKit

/// 截图/拍照入账直通流程（文档 F-12/F-15 重构）：
/// source=album → 直接打开系统相册选择器（无中间选项卡）
/// source=camera → 先相机拍摄
/// 选/拍完成后自动识别 → 草稿逐笔确认（含防重/商户记忆/渠道徽章）
struct QuickCaptureView: View {
    enum Source { case album, camera }
    enum Stage { case picking, review }

    let source: Source

    @Environment(\.modelContext) private var context
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    @State private var stage: Stage = .picking
    @State private var entries: [DraftEntry] = []
    @State private var processing = false
    @State private var savedCount = 0
    @State private var categoryTarget: CategoryTarget?
    @State private var pendingDuplicate: DuplicateMatch?
    @State private var confirmEntryID: DraftEntry.ID?
    @State private var duplicateBlockMessage: String?

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
            switch stage {
            case .picking:
                pickingStage
            case .review:
                reviewStage
            }
        }
        .navigationTitle(source == .camera ? "拍照入账" : "截图入账")
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
            onConfirm: {
                guard let id = confirmEntryID,
                      let index = entries.firstIndex(where: { $0.id == id }),
                      let cents = Money.cents(fromString: entries[index].amountText), cents > 0,
                      let account = resolveAccount(for: entries[index]) else { return }
                commit(entries[index], cents: cents, account: account)
            }
        ))
    }

    // MARK: - 选图阶段

    @ViewBuilder
    private var pickingStage: some View {
        switch source {
        case .album:
            PhotoLibraryPicker(maxCount: 5) { images in
                Task { await handleImages(images) }
            }
            .ignoresSafeArea()
        case .camera:
            CameraPicker(
                onImage: { image in
                    Task { await handleImages([image]) }
                },
                onCancel: { }
            )
            .ignoresSafeArea()
        }
        if processing {
            VStack(spacing: 10) {
                ProgressView()
                Text("识别中…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 30)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - 确认阶段

    @ViewBuilder
    private var reviewStage: some View {
        List {
            if entries.isEmpty {
                Section {
                    if savedCount > 0 {
                        Label("本次已保存 \(savedCount) 笔", systemImage: "checkmark.seal")
                            .foregroundStyle(Theme.income)
                    } else {
                        EmptyStateView(icon: "photo.badge.exclamationmark",
                                       title: "没有识别出可入账的内容",
                                       hint: "返回后可重新选择截图，或改用手动录入")
                    }
                }
            }
            ForEach($entries) { $entry in
                entrySection($entry)
            }
        }
    }

    private func entrySection(_ entry: Binding<DraftEntry>) -> some View {
        Section {
            Picker("类型", selection: entry.kind) {
                Text("支出").tag(TxKind.expense)
                Text("收入").tag(TxKind.income)
            }
            .pickerStyle(.segmented)
            TextField("金额（元）", text: entry.amountText)
                .keyboardType(.decimalPad)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            DatePicker("时间", selection: entry.date)
            TextField("收款方/商户", text: entry.counterparty)
            TextField("备注", text: entry.note)
            if let channel = entry.wrappedValue.channel {
                HStack {
                    Text("渠道")
                    Spacer()
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(hex: channel.colorHex))
                            .frame(width: 6, height: 6)
                        Text(channel.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                Text("账户")
                Spacer()
                Menu(entry.wrappedValue.account?.name ?? "请选择") {
                    ForEach(activeAccounts) { account in
                        Button(account.name) {
                            entry.wrappedValue.account = account
                        }
                    }
                }
                .foregroundStyle(entry.wrappedValue.account == nil ? Color.orange : Color.primary)
            }
            HStack {
                Text("分类")
                Spacer()
                Button(entry.wrappedValue.category?.name ?? "未分类") {
                    categoryTarget = CategoryTarget(entryID: entry.wrappedValue.id)
                }
                .foregroundStyle(entry.wrappedValue.category == nil ? .secondary : .primary)
            }
            if !entry.wrappedValue.warning.isEmpty {
                Label(entry.wrappedValue.warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Theme.alert)
            }
            Button {
                save(entry.wrappedValue)
            } label: {
                Text("确认入账")
                    .frame(maxWidth: .infinity)
                    .fontWeight(.medium)
            }
            .disabled(!canSave(entry.wrappedValue))
        }
    }

    // MARK: - 数据与动作

    private var activeAccounts: [Account] {
        accounts.filter { !$0.isArchived }
    }

    /// 渠道 → 默认账户（文档 v1.4 渠道识别）
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

        let match = DuplicateGuard.findDuplicate(of: entry.kind,
                                                 amountCents: cents,
                                                 date: entry.date,
                                                 in: history)
        switch DuplicateGuard.manualDecision(for: match) {
        case .allow:
            commit(entry, cents: cents, account: account)
        case .confirm(let duplicated):
            pendingDuplicate = duplicated
            confirmEntryID = entry.id
        case .block(let duplicated):
            duplicateBlockMessage = "已存在 \(duplicated.summary)。当前防重策略为「阻止」，如确需保存请在「我的 → 自动记账」中调整灵敏度。"
        }
    }

    private var history: [Transaction] {
        (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
    }

    private func commit(_ entry: DraftEntry, cents: Int64, account: Account) {
        // F-18 商户记忆：分类未选时按商户名匹配历史分类预填
        var entry = entry
        if entry.category == nil, !entry.counterparty.isEmpty {
            entry.category = CategoryPredictor.category(forMerchant: entry.counterparty, in: history)
        }

        let noteText = entry.note.isEmpty ? entry.counterparty : entry.note
        let tx = Transaction(kind: entry.kind,
                             amountCents: cents,
                             date: entry.date,
                             account: account,
                             category: entry.category,
                             note: noteText,
                             source: .ocr,
                             channel: entry.channel)
        context.insert(tx)
        try? context.save()
        AutoPostStore.shared.recordPosted(txID: tx.id, kind: entry.kind,
                                          amountCents: cents, date: entry.date,
                                          note: noteText)
        savedCount += 1
        entries.removeAll { $0.id == entry.id }
    }

        private func handleImages(_ images: [UIImage]) {
        processing = true
        Task { @MainActor in
            var drafts: [DraftEntry] = []
            for image in images {
                for row in await SmartExtractionService.extractRows(from: image) {
                    drafts.append(makeEntry(from: row))
                }
            }
            entries.append(contentsOf: drafts)
            processing = false
            stage = .review
        }
    }

    private func makeEntry(from row: PaymentTextParser.ParsedPayment) -> DraftEntry {
        var warning = ""
        if (row.amountCents ?? 0) <= 0 {
            warning = "未识别出金额，请手动补填"
        }
        return DraftEntry(kind: row.kind ?? .expense,
                          amountText: row.amountCents.map { Money.inputString(fromCents: $0) } ?? "",
                          date: row.date ?? Date(),
                          counterparty: row.counterparty ?? "",
                          note: row.note ?? "",
                          channel: row.channel,
                          category: nil,
                          account: activeAccounts.first,
                          warning: warning)
    }
}
