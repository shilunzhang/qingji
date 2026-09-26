import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// 账单导入（文档 F-10）：选择 CSV -> 解析预览 -> 支付方式映射账户 -> 查重导入
struct ImportView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    @State private var showImporter = false
    @State private var result: BillParseResult?
    @State private var errorMessage: String?
    @State private var methodMap: [String: Account] = [:]
    @State private var importedCount = 0

    var body: some View {
        List {
            importedBanner
            if let result {
                summarySection(result)
                mappingSection(result)
                previewSection(result)
                importSection(result)
            } else {
                introSection
            }
        }
        .navigationTitle("账单导入")
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [UTType.data],
                      allowsMultipleSelection: false) { selection in
            handleSelection(selection)
        }
        .alert("导入失败", isPresented: errorAlert) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var errorAlert: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    @ViewBuilder
    private var importedBanner: some View {
        if importedCount > 0 && result == nil {
            Section {
                Label("已导入 \(importedCount) 笔账目，可在明细页查看", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.income)
            }
        }
    }

    // MARK: - 数据

    private var dedupContext: BillDedupContext {
        BillDedup.makeContext(for: transactions)
    }

    private func isDuplicate(_ row: ParsedBillRow, context dedup: BillDedupContext) -> Bool {
        BillDedup.isDuplicate(row, context: dedup)
    }

    private func methods(in parseResult: BillParseResult) -> [String] {
        Array(Set(parseResult.rows.map(\.payMethod)).filter { !$0.isEmpty }).sorted()
    }

    private var activeAccounts: [Account] { accounts.filter { !$0.isArchived } }

    // MARK: - 视图

    private var introSection: some View {
        Section {
            Button {
                showImporter = true
            } label: {
                Label("选择账单文件（CSV）", systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity)
            }
        } header: {
            Text("开始")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("支付宝：我的 → 账单 → 右上角「…」→ 开具交易流水证明 → 用于个人对账，邮箱下载 CSV")
                Text("微信：服务 → 钱包 → 账单 → 右上角「常见问题」→ 下载账单，邮箱获取 CSV")
                Text("导入时自动剔除转账/退款/未完成记录，并按流水号与时间金额查重")
            }
        }
    }

    private func mappingSection(_ parseResult: BillParseResult) -> some View {
        Section {
            ForEach(methods(in: parseResult), id: \.self) { method in
                HStack {
                    Text(method)
                        .lineLimit(1)
                    Spacer()
                    methodMenu(method)
                }
            }
        } header: {
            Text("支付方式 → 账户")
        } footer: {
            Text("未列出的支付方式将使用默认账户")
        }
    }

    @ViewBuilder
    private func methodMenu(_ method: String) -> some View {
        let current = methodMap[method]?.name ?? "选择账户"
        Menu(current) {
            ForEach(activeAccounts) { account in
                Button {
                    methodMap[method] = account
                } label: {
                    HStack {
                        Text(account.name)
                        if methodMap[method]?.id == account.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
        .foregroundStyle(Color.accentColor)
    }

    private func importSection(_ parseResult: BillParseResult) -> some View {
        let dedup = dedupContext
        let importable = parseResult.rows.filter { !isDuplicate($0, context: dedup) }.count
        let title = importable > 0 ? "导入 \(importable) 笔" : "没有可导入的新账目"
        return Section {
            Button {
                performImport(parseResult)
            } label: {
                Text(title)
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
            }
            .disabled(importable == 0 || activeAccounts.isEmpty)
        }
    }

    private func summarySection(_ parseResult: BillParseResult) -> some View {
        let dedup = dedupContext
        let duplicates = parseResult.rows.filter { isDuplicate($0, context: dedup) }.count
        let expense = parseResult.rows.filter { $0.kind == .expense }.reduce(Int64(0)) { $0 + $1.amountCents }
        let income = parseResult.rows.filter { $0.kind == .income }.reduce(Int64(0)) { $0 + $1.amountCents }
        let importable = parseResult.rows.count - duplicates
        return Section {
            LabeledContent("来源", value: parseResult.source.rawValue)
            LabeledContent("可导入", value: "\(importable) 笔")
            LabeledContent("重复跳过", value: "\(duplicates) 笔")
                .foregroundStyle(duplicates > 0 ? Color.orange : Color.primary)
            LabeledContent("支出合计", value: Money.string(fromCents: expense))
            LabeledContent("收入合计", value: Money.string(fromCents: income))
            LabeledContent("自动剔除", value: "\(parseResult.skippedLines) 行")
                .foregroundStyle(.secondary)
        }
    }

    private func previewSection(_ parseResult: BillParseResult) -> some View {
        let dedup = dedupContext
        let preview = Array(parseResult.rows.prefix(50))
        return Section {
            ForEach(preview.indices, id: \.self) { index in
                billRow(preview[index], duplicate: isDuplicate(preview[index], context: dedup))
            }
            if parseResult.rows.count > 50 {
                Text("仅预览前 50 条，导入时包含全部")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        } header: {
            Text("预览")
        }
    }

    private func billRow(_ row: ParsedBillRow, duplicate: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(rowText(row))
                    .font(.subheadline)
                    .lineLimit(1)
                Text(dateText(row.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if duplicate {
                Text("重复")
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(Capsule())
                    .foregroundStyle(Color.orange)
            }
            AmountText(row.amountCents, kind: row.kind, font: .subheadline.weight(.medium))
        }
    }

    private func rowText(_ row: ParsedBillRow) -> String {
        row.counterparty.isEmpty ? row.product : row.counterparty
    }

    // MARK: - 动作

    private func handleSelection(_ selection: Result<[URL], Error>) {
        guard let url = (try? selection.get())?.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let parsed = try BillParser.parse(data: data)
            result = parsed
            importedCount = 0
            buildDefaultMappings(parsed)
            errorMessage = nil
        } catch {
            result = nil
            errorMessage = error.localizedDescription
        }
    }

    private func buildDefaultMappings(_ result: BillParseResult) {
        methodMap = [:]
        for method in Set(result.rows.map(\.payMethod)) where !method.isEmpty {
            methodMap[method] = guessAccount(for: method)
        }
    }

    private func guessAccount(for method: String) -> Account? {
        func firstKind(_ kind: AccountKind) -> Account? {
            activeAccounts.first { $0.kind == kind }
        }
        if method.contains("零钱") { return firstKind(.wechat) ?? activeAccounts.first }
        if method.contains("余额宝") || method.contains("余额") || method.contains("花呗")
            || method.contains("支付宝") { return firstKind(.alipay) ?? activeAccounts.first }
        if method.contains("信用卡") { return firstKind(.credit) ?? activeAccounts.first }
        if method.contains("卡") || method.contains("银行") { return firstKind(.bank) ?? activeAccounts.first }
        return activeAccounts.first
    }

    private func performImport(_ parseResult: BillParseResult) {
        let dedup = dedupContext
        var batchSeen: Set<String> = []
        let fallback = activeAccounts.first
        var created = 0

        for row in parseResult.rows {
            if isDuplicate(row, context: dedup) { continue }
            let key = BillDedup.fuzzyKey(kind: row.kind, date: row.date, amountCents: row.amountCents)
            guard batchSeen.insert(key).inserted else { continue } // 批内分钟级去重
            guard let account = methodMap[row.payMethod] ?? fallback else { break }

            let summary = [row.counterparty, row.product].filter { !$0.isEmpty }.joined(separator: " · ")
            let note = row.note.isEmpty ? summary : (summary.isEmpty ? row.note : "\(summary)（\(row.note)）")
            context.insert(Transaction(kind: row.kind,
                                       amountCents: row.amountCents,
                                       date: row.date,
                                       account: account,
                                       category: nil,
                                       note: note,
                                       externalID: row.externalID,
                                       source: .bill))
            created += 1
        }
        try? context.save()
        importedCount = created
        result = nil
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }
}
