import SwiftUI
import SwiftData
import UIKit

/// 截图/拍照入账（文档 F-12/F-15）
/// 打开即弹相册/相机，无中间页面；取消则直接关闭
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
    @State private var showPicker = false
    @State private var categoryTarget: CategoryTarget?
    @State private var pendingDuplicate: DuplicateMatch?
    @State private var confirmEntryID: DraftEntry.ID?
    @State private var duplicateBlockMessage: String?
    // 修复C/E：空态与呈现竞争追踪
    @State private var hasAttempted = false      // 已选过图片（无论是否识别出记录）
    @State private var pickerAppeared = false    // 内层选择器确实弹出过
    @State private var autoPresentFailed = false // 自动弹出失败的兜底标记

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
            } else {
                fallbackView
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        // 修复B：下拉滑动取消不会触发任何回调，onDismiss 是唯一的取消出口
        .sheet(isPresented: $showPicker, onDismiss: handlePickerDismissed) {
            Group {
                if source == .camera && !CameraPicker.isAvailable {
                    // 修复E：模拟器/无摄像头设备直接弹相册选择器，避免崩溃
                    PhotoLibraryPicker(maxCount: 5) { images in
                        showPicker = false
                        if !images.isEmpty {
                            handleImages(images)
                        }
                    }
                } else if source == .album {
                    PhotoLibraryPicker(maxCount: 5) { images in
                        showPicker = false
                        if !images.isEmpty {
                            handleImages(images)
                        }
                        // 空选择：交给 onDismiss 统一关闭整页
                    }
                } else {
                    CameraPicker(
                        onImage: { image in
                            showPicker = false
                            handleImages([image])
                        },
                        onCancel: {
                            // 取消：仅收回选择器，由 onDismiss 统一关闭整页
                            // （避免在子 sheet 动画中同时 dismiss 父视图产生竞态）
                            showPicker = false
                        }
                    )
                }
            }
            .onAppear { pickerAppeared = true }
            .onDisappear { pickerAppeared = false }
        }
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
        .task {
            // 修复E：等外层 sheet 完成呈现后再弹内层选择器，避免呈现竞争被系统丢弃
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            showPicker = true
            // 兜底：若竞争导致选择器没弹出，给出手动入口，杜绝空白死页
            try? await Task.sleep(for: .seconds(1))
            if !pickerAppeared && !processing {
                autoPresentFailed = true
            }
        }
    }

    /// 选择器关闭后的统一出口：
    /// 无识别结果、无保存、不在处理中 → 整页关闭，回到主页（不留残留页）
    private func handlePickerDismissed() {
        pickerAppeared = false
        if entries.isEmpty && savedCount == 0 && !processing {
            dismiss()
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
            DatePicker("时间", selection: entry.date)
            TextField("收款方/商户", text: entry.counterparty)
            HStack {
                Text("账户")
                Spacer()
                Menu(entry.wrappedValue.account?.name ?? "请选择") {
                    ForEach(activeAccounts) { account in
                        Button(account.name) { entry.wrappedValue.account = account }
                    }
                }
            }
            HStack {
                Text("分类")
                Spacer()
                Button(entry.wrappedValue.category?.name ?? "未分类") {
                    categoryTarget = CategoryTarget(entryID: entry.wrappedValue.id)
                }
                .foregroundStyle(.secondary)
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

    // MARK: - 空态兜底（修复C）

    /// 需要给用户出口的状态：识别到 0 条 / 相机不可用 / 选择器没自动弹出。
    /// 其余等待期保持空白（瞬时状态，选择器马上盖上来）。
    @ViewBuilder
    private var fallbackView: some View {
        if needsFallback {
            VStack(spacing: 14) {
                Image(systemName: fallbackIcon)
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text(fallbackTitle).font(.headline)
                if hasAttempted && !cameraUnavailable {
                    Text("换一张支付成功页截图试试，或改用手动记账")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Button("重新选择") {
                    hasAttempted = false
                    autoPresentFailed = false
                    showPicker = true
                }
                .buttonStyle(.borderedProminent)
                Button("关闭") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemBackground))
        } else {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
        }
    }

    private var cameraUnavailable: Bool {
        source == .camera && !CameraPicker.isAvailable
    }

    private var needsFallback: Bool {
        hasAttempted || cameraUnavailable || autoPresentFailed
    }

    private var fallbackIcon: String {
        if cameraUnavailable { return "video.slash" }
        if autoPresentFailed { return "photo.on.rectangle" }
        return "text.viewfinder"
    }

    private var fallbackTitle: String {
        if cameraUnavailable { return "相机不可用，已切换为相册选择" }
        if autoPresentFailed { return "没有自动打开选择器" }
        return "未识别到账单记录"
    }

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
        Task { @MainActor in
            var drafts: [DraftEntry] = []
            for image in images {
                for row in await SmartExtractionService.extractRows(from: image) {
                    drafts.append(makeEntry(from: row))
                }
            }
            entries.append(contentsOf: drafts)
            hasAttempted = true   // 无论是否识别出记录，都标记已尝试（0 条时给兜底出口）
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
