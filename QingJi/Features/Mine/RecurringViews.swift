import SwiftUI
import SwiftData

/// 周期记账列表（文档 F-07）
struct RecurringListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \RecurringRule.createdAt, order: .reverse) private var rules: [RecurringRule]

    @State private var addingRule = false

    var body: some View {
        List {
            ForEach(rules) { rule in
                NavigationLink {
                    RecurringRuleEditorView(rule: rule)
                } label: {
                    row(rule)
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    context.delete(rules[index])
                }
                try? context.save()
            }

            if rules.isEmpty {
                EmptyStateView(icon: "arrow.triangle.2.circlepath",
                               title: "还没有周期规则",
                               hint: "房租、工资、会员订阅这类固定收支交给它")
            }
        }
        .navigationTitle("周期记账")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    addingRule = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $addingRule) {
            RecurringRuleEditorView(rule: nil)
        }
        .onAppear {
            // 列表页进入时也尝试补账（与启动时双保险）
            RecurringEngine.postDueRules(rules: rules, context: context)
        }
    }

    private func row(_ rule: RecurringRule) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(rule.name.isEmpty ? "未命名规则" : rule.name)
                    .font(.subheadline.weight(.medium))
                Spacer()
                AmountText(rule.amountCents, kind: rule.kind, font: .subheadline.weight(.semibold))
            }
            HStack {
                Text(frequencyText(rule))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(nextDateText(rule))
                    .font(.caption)
                    .foregroundStyle(rule.isActive ? .secondary : .tertiary)
            }
        }
        .opacity(rule.isActive ? 1 : 0.5)
    }

    private func frequencyText(_ rule: RecurringRule) -> String {
        switch rule.frequency {
        case .daily:
            return rule.intervalDays > 1 ? "每 \(rule.intervalDays) 天" : "每天"
        case .weekly:
            let index = max(0, min(6, rule.weekday - 1))
            return "每 周\(DateHelpers.weekdayTitles[index])"
        case .monthly:
            return "每月 \(rule.dayOfMonth) 号"
        case .yearly:
            return "每年 \(rule.dayOfMonth) 号"
        }
    }

    private func nextDateText(_ rule: RecurringRule) -> String {
        guard rule.isActive else { return "已停用" }
        guard let next = RecurringEngine.nextDueDate(of: rule, after: rule.lastPostedDate ?? rule.startDate) else {
            return "已结束"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return "下次 \(formatter.string(from: next))"
    }
}

/// 周期规则编辑器（新建/编辑共用）
struct RecurringRuleEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    private let existing: RecurringRule?

    @State private var name = ""
    @State private var kind: TxKind = .expense
    @State private var amountText = ""
    @State private var frequency: RecurringFrequency = .monthly
    @State private var dayOfMonth = 1
    @State private var weekday = 1
    @State private var intervalDays = 1
    @State private var startDate = Date()
    @State private var hasEndDate = false
    @State private var endDate = Date()
    @State private var note = ""
    @State private var isActive = true
    @State private var selectedCategory: Category?
    @State private var selectedAccount: Account?
    @State private var showCategoryPicker = false
    @State private var showAccountPicker = false
    @State private var didLoad = false

    init(rule: RecurringRule?) {
        self.existing = rule
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("名称（如：房租）", text: $name)
                    Picker("类型", selection: $kind) {
                        Text("支出").tag(TxKind.expense)
                        Text("收入").tag(TxKind.income)
                    }
                    .pickerStyle(.segmented)
                    TextField("金额（元）", text: $amountText)
                        .keyboardType(.decimalPad)
                        .monospacedDigit()
                    Button {
                        showCategoryPicker = true
                    } label: {
                        HStack {
                            Text("分类").foregroundStyle(.primary)
                            Spacer()
                            Text(selectedCategory?.name ?? "请选择")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        showAccountPicker = true
                    } label: {
                        HStack {
                            Text("账户").foregroundStyle(.primary)
                            Spacer()
                            Text(selectedAccount?.name ?? "请选择")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("周期") {
                    Picker("频率", selection: $frequency) {
                        ForEach(RecurringFrequency.allCases) { f in
                            Text(f.title).tag(f)
                        }
                    }
                    switch frequency {
                    case .daily:
                        Stepper("每 \(intervalDays) 天", value: $intervalDays, in: 1...365)
                    case .weekly:
                        Picker("星期", selection: $weekday) {
                            ForEach(Array(DateHelpers.weekdayTitles.enumerated()), id: \.offset) { index, title in
                                Text("周\(title)").tag(index + 1)
                            }
                        }
                    case .monthly, .yearly:
                        Stepper("每月 \(dayOfMonth) 号", value: $dayOfMonth, in: 1...31)
                    }
                    DatePicker("开始日期", selection: $startDate, displayedComponents: .date)
                    Toggle("设置结束日期", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("结束日期", selection: $endDate, displayedComponents: .date)
                    }
                }

                Section {
                    TextField("备注", text: $note)
                    Toggle("启用", isOn: $isActive)
                    if let next = nextDateText {
                        LabeledContent("下次执行", value: next)
                    }
                    Button("立即入账一次") { postOnceNow() }
                        .disabled(existing == nil || !canSave)
                } footer: {
                    Text("启用后 App 启动时会自动补齐到期账目，漏开 App 也会逐期补上")
                }
            }
            .navigationTitle(existing == nil ? "新建规则" : "编辑规则")
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
                CategoryPickerSheet(selected: selectedCategory, defaultKind: kind == .income ? .income : .expense) { picked in
                    selectedCategory = picked
                }
            }
            .sheet(isPresented: $showAccountPicker) {
                AccountPickerSheet(title: "选择账户", selected: selectedAccount) { picked in
                    selectedAccount = picked
                }
            }
            .onAppear(perform: load)
        }
    }

    private var canSave: Bool {
        guard let cents = Money.cents(fromString: amountText), cents > 0 else { return false }
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard selectedAccount != nil else { return false }
        if hasEndDate { return endDate >= startDate }
        return true
    }

    private var nextDateText: String? {
        guard let rule = existing else { return nil }
        // 用临时对象按当前表单值计算预览，避免渲染期间修改模型
        let temp = RecurringRule(name: name,
                                 kind: kind,
                                 amountCents: Money.cents(fromString: amountText) ?? 0,
                                 frequency: frequency,
                                 dayOfMonth: dayOfMonth,
                                 weekday: weekday,
                                 intervalDays: intervalDays,
                                 startDate: startDate,
                                 endDate: hasEndDate ? endDate : nil)
        guard let next = RecurringEngine.nextDueDate(of: temp, after: rule.lastPostedDate ?? startDate) else {
            return "已结束"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: next)
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let rule = existing else {
            selectedAccount = accounts.first { !$0.isArchived }
            return
        }
        name = rule.name
        kind = rule.kind == .transfer ? .expense : rule.kind
        amountText = Money.inputString(fromCents: rule.amountCents)
        frequency = rule.frequency
        dayOfMonth = rule.dayOfMonth
        weekday = rule.weekday
        intervalDays = rule.intervalDays
        startDate = rule.startDate
        note = rule.note
        isActive = rule.isActive
        selectedCategory = rule.category
        selectedAccount = rule.account
        if let end = rule.endDate {
            hasEndDate = true
            endDate = end
        }
    }

    /// 把当前表单同步到规则对象（用于预览下次执行时间）
    private func syncToRule() {
        guard let rule = existing else { return }
        rule.name = name
        rule.kindRaw = kind.rawValue
        rule.amountCents = Money.cents(fromString: amountText) ?? rule.amountCents
        rule.frequencyRaw = frequency.rawValue
        rule.dayOfMonth = dayOfMonth
        rule.weekday = weekday
        rule.intervalDays = intervalDays
        rule.startDate = startDate
        rule.endDate = hasEndDate ? endDate : nil
        rule.note = note
        rule.isActive = isActive
        rule.category = selectedCategory
        rule.account = selectedAccount
    }

    private func save() {
        guard canSave else { return }
        syncToRule()
        if existing == nil {
            let rule = RecurringRule(name: name,
                                     kind: kind,
                                     amountCents: Money.cents(fromString: amountText) ?? 0,
                                     frequency: frequency,
                                     dayOfMonth: dayOfMonth,
                                     weekday: weekday,
                                     intervalDays: intervalDays,
                                     startDate: startDate,
                                     endDate: hasEndDate ? endDate : nil,
                                     note: note)
            rule.isActive = isActive
            rule.category = selectedCategory
            rule.account = selectedAccount
            context.insert(rule)
        }
        try? context.save()
        dismiss()
    }

    /// 手动把下一期入账（文档 F-07）
    private func postOnceNow() {
        guard let rule = existing else { return }
        syncToRule()
        let after = rule.lastPostedDate ?? rule.startDate
        guard let due = RecurringEngine.nextDueDate(of: rule, after: after) else { return }
        let tx = Transaction(kind: rule.kind,
                             amountCents: rule.amountCents,
                             date: due,
                             account: rule.account,
                             category: rule.category,
                             note: rule.note,
                             recurringRuleID: rule.id)
        context.insert(tx)
        rule.lastPostedDate = due
        try? context.save()
    }
}
