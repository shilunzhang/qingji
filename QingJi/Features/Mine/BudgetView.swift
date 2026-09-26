import SwiftUI
import SwiftData

/// 预算管理（文档 F-06）：总预算 + 分类预算，月度进度
struct BudgetView: View {
    @Environment(\.modelContext) private var context
    @Query private var budgets: [Budget]
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    @State private var editingOverall: Budget?
    @State private var addingOverall = false
    @State private var addingCategoryBudget = false

    var body: some View {
        List {
            overallSection
            categorySection
        }
        .navigationTitle("预算管理")
        .sheet(item: $editingOverall) { budget in
            BudgetEditorView(budget: budget, category: nil)
        }
        .sheet(isPresented: $addingOverall) {
            BudgetEditorView(budget: nil, category: nil)
        }
        .sheet(isPresented: $addingCategoryBudget) {
            BudgetEditorView(budget: nil, category: nil)
        }
    }

    // MARK: - 数据

    private var monthRange: (start: Date, end: Date) {
        DateHelpers.range(of: .month, containing: Date())
    }

    private var monthTx: [Transaction] {
        LedgerService.transactions(transactions, in: monthRange)
    }

    private var monthExpense: Int64 {
        LedgerService.totals(in: monthTx).expense
    }

    /// 分类 -> 当月支出
    private var categoryMonthExpense: [UUID: Int64] {
        var result: [UUID: Int64] = [:]
        for tx in monthTx where tx.type == .expense {
            guard let cat = tx.category else { continue }
            result[cat.id, default: 0] += tx.amountCents
        }
        return result
    }

    private var overallBudget: Budget? {
        budgets.first { $0.scope == .overall }
    }

    private var categoryBudgets: [Budget] {
        budgets.filter { $0.scope == .category && $0.category != nil }
            .sorted { ($0.category?.sortOrder ?? 0) < ($1.category?.sortOrder ?? 0) }
    }

    /// 可添加预算的支出分类（未设置的父分类）
    private var availableCategories: [Category] {
        let used = Set(categoryBudgets.compactMap { $0.category?.id })
        return categories.filter { $0.kindRaw == CategoryKind.expense.rawValue && $0.parent == nil && !used.contains($0.id) }
    }

    // MARK: - 视图

    private var overallSection: some View {
        Section {
            if let budget = overallBudget {
                Button {
                    editingOverall = budget
                } label: {
                    progressRow(title: "总预算",
                                budget: budget.amountCents,
                                spent: monthExpense,
                                colorHex: "FF8A3D")
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    addingOverall = true
                } label: {
                    Label("设置本月总预算", systemImage: "plus.circle")
                }
            }
        } header: {
            Text("本月总预算")
        } footer: {
            Text("当前已支出 \(Money.string(fromCents: monthExpense))")
        }
    }

    private var categorySection: some View {
        Section {
            ForEach(categoryBudgets) { budget in
                if let category = budget.category {
                    NavigationLink {
                        BudgetEditorView(budget: budget, category: category)
                    } label: {
                        progressRow(title: category.name,
                                    budget: budget.amountCents,
                                    spent: categoryMonthExpense[category.id] ?? 0,
                                    colorHex: category.colorHex)
                    }
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    context.delete(categoryBudgets[index])
                }
                try? context.save()
            }

            if !availableCategories.isEmpty {
                Button {
                    addingCategoryBudget = true
                } label: {
                    Label("添加分类预算", systemImage: "plus.circle")
                }
            }
        } header: {
            Text("分类预算")
        }
    }

    private func progressRow(title: String, budget: Int64, spent: Int64, colorHex: String) -> some View {
        let ratio = budget > 0 ? Double(spent) / Double(budget) : 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Money.string(fromCents: spent)) / \(Money.string(fromCents: budget))")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(ratio > 1 ? Theme.alert : .primary)
            }
            ProgressView(value: min(ratio, 1))
                .tint(ratio > 1 ? Theme.alert : Color(hex: colorHex))
            Text(ratio > 1
                 ? "已超支 \(Money.string(fromCents: spent - budget))"
                 : "剩余 \(Money.string(fromCents: max(0, budget - spent)))")
                .font(.caption)
                .foregroundStyle(ratio > 1 ? Theme.alert : .secondary)
        }
        .padding(.vertical, 2)
    }
}

/// 预算编辑器：category 为 nil 表示总预算（新建时由用户在「添加分类预算」选择）
struct BudgetEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    /// 待编辑预算；nil = 新建
    private let existing: Budget?
    /// 新建时是否为分类预算（总预算入口传 nil 且 isCategoryBudget=false）
    private let isCategoryBudget: Bool

    @State private var amountText = ""
    @State private var selectedCategory: Category?
    @State private var showCategoryPicker = false

    init(budget: Budget?, category: Category?) {
        self.existing = budget
        // 总预算编辑入口：budget != nil && category == nil 且 budget.scope == .overall
        self.isCategoryBudget = category != nil || (budget?.scope == .category)
        _selectedCategory = State(initialValue: category ?? budget?.category)
        _amountText = State(initialValue: (budget?.amountCents ?? 0) > 0
                            ? Money.inputString(fromCents: budget?.amountCents ?? 0)
                            : "")
    }

    var body: some View {
        NavigationStack {
            Form {
                if isCategoryBudget {
                    Section("分类") {
                        Button {
                            showCategoryPicker = true
                        } label: {
                            HStack {
                                Text("选择分类")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(selectedCategory?.name ?? "请选择")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(existing != nil) // 已建预算不换分类，删除重建
                    }
                }
                Section("月度金额（元）") {
                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .monospacedDigit()
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showCategoryPicker) {
                CategoryPickerSheet(selected: selectedCategory, defaultKind: .expense) { picked in
                    selectedCategory = picked
                }
            }
        }
    }

    private var title: String {
        if existing != nil { return isCategoryBudget ? "编辑分类预算" : "编辑总预算" }
        return isCategoryBudget ? "添加分类预算" : "设置总预算"
    }

    private var canSave: Bool {
        guard let cents = Money.cents(fromString: amountText), cents > 0 else { return false }
        if isCategoryBudget && existing == nil { return selectedCategory != nil }
        return true
    }

    private func save() {
        guard let cents = Money.cents(fromString: amountText), cents > 0 else { return }
        if let budget = existing {
            budget.amountCents = cents
        } else if isCategoryBudget {
            // 同分类旧预算先清理
            if let category = selectedCategory,
               let old = (try? context.fetch(FetchDescriptor<Budget>()))?.first(where: { $0.category?.id == category.id }) {
                context.delete(old)
            }
            context.insert(Budget(amountCents: cents, category: selectedCategory))
        } else {
            context.insert(Budget(amountCents: cents, category: nil))
        }
        try? context.save()
        dismiss()
    }
}
