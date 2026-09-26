import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// 截图记账（文档 F-09 App 内路径）：选支付截图 -> Vision OCR -> 预填草稿 -> 确认保存
struct ScreenshotImportView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var entries: [DraftEntry] = []
    @State private var processing = false
    @State private var savedCount = 0

    /// sheet(item:) 要求 Identifiable，UUID 本身不满足，用包装类型
    private struct CategoryTarget: Identifiable {
        let entryID: DraftEntry.ID
        var id: DraftEntry.ID { entryID }
    }

    @State private var categoryTarget: CategoryTarget?

    struct DraftEntry: Identifiable {
        let id = UUID()
        var amountText: String
        var date: Date
        var counterparty: String
        var category: Category?
        var account: Account?
        var warning: String
    }

    var body: some View {
        List {
            Section {
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 5, matching: .images) {
                    Label("选择支付截图", systemImage: "photo.on.rectangle.angled")
                        .frame(maxWidth: .infinity)
                }
                if processing {
                    HStack {
                        ProgressView()
                        Text("识别中…")
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("支持支付宝/微信等支付成功页截图，自动识别金额、时间与收款方，识别后可修改再保存")
            }

            ForEach($entries) { $entry in
                entrySection($entry)
            }

            if savedCount > 0 {
                Section {
                    Label("本次已保存 \(savedCount) 笔", systemImage: "checkmark.seal")
                        .foregroundStyle(Theme.income)
                }
            }
        }
        .navigationTitle("截图记账")
        .onChange(of: pickerItems.count) { _, _ in
            if !pickerItems.isEmpty {
                processItems()
            }
        }
        .sheet(item: $categoryTarget) { target in
            CategoryPickerSheet(selected: nil, defaultKind: .expense) { picked in
                if let index = entries.firstIndex(where: { $0.id == target.entryID }) {
                    entries[index].category = picked
                }
            }
        }
    }

    // MARK: - 草稿行

    private func entrySection(_ entry: Binding<DraftEntry>) -> some View {
        Section {
            TextField("金额（元）", text: entry.amountText)
                .keyboardType(.decimalPad)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            DatePicker("时间", selection: entry.date)
            TextField("收款方/备注", text: entry.counterparty)
            HStack {
                Text("账户")
                Spacer()
                Menu(entry.wrappedValue.account?.name ?? "请选择") {
                    ForEach(accounts.filter { !$0.isArchived }) { account in
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
                Label("保存这笔", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity)
                    .fontWeight(.medium)
            }
            .disabled(!canSave(entry.wrappedValue))
        }
    }

    private func canSave(_ entry: DraftEntry) -> Bool {
        guard let cents = Money.cents(fromString: entry.amountText), cents > 0 else { return false }
        return entry.account != nil || !accounts.filter { !$0.isArchived }.isEmpty
    }

    private func save(_ entry: DraftEntry) {
        guard let cents = Money.cents(fromString: entry.amountText), cents > 0 else { return }
        guard let account = entry.account ?? accounts.first(where: { !$0.isArchived }) else { return }
        context.insert(Transaction(kind: .expense,
                                   amountCents: cents,
                                   date: entry.date,
                                   account: account,
                                   category: entry.category,
                                   note: entry.counterparty,
                                   source: .ocr))
        try? context.save()
        savedCount += 1
        entries.removeAll { $0.id == entry.id }
    }

    // MARK: - 识别流程

    private func processItems() {
        let items = pickerItems
        pickerItems = []
        processing = true
        Task {
            var drafts: [DraftEntry] = []
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                let parsed = await recognize(data)
                drafts.append(makeEntry(from: parsed))
            }
            await MainActor.run {
                entries.append(contentsOf: drafts)
                processing = false
            }
        }
    }

    private func makeEntry(from parsed: PaymentTextParser.ParsedPayment) -> DraftEntry {
        var warning = ""
        if parsed.amountCents == nil { warning = "未识别出金额，请手动补填" }
        return DraftEntry(amountText: parsed.amountCents.map { Money.inputString(fromCents: $0) } ?? "",
                          date: parsed.date ?? Date(),
                          counterparty: parsed.counterparty ?? "",
                          category: nil,
                          account: accounts.first { !$0.isArchived },
                          warning: warning)
    }

    private func recognize(_ data: Data) async -> PaymentTextParser.ParsedPayment {
        // OCR 前缩放，提速且不影响识别率
        guard let compressed = AddTransactionView.compress(imageData: data, maxDimension: 1600),
              let image = UIImage(data: compressed) else {
            return PaymentTextParser.ParsedPayment()
        }
        return await withCheckedContinuation { continuation in
            OCRService.recognizeText(in: image) { result in
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
