import SwiftUI
import SwiftData

/// 账户管理（文档 F-02）：M1 不提供删除（防流水悬空），提供归档
struct AccountManageView: View {
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    @State private var adding = false

    var body: some View {
        List {
            ForEach(accounts) { account in
                NavigationLink {
                    AccountEditorView(account: account)
                } label: {
                    HStack {
                        IconBadge(icon: account.icon, colorHex: account.colorHex)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.name)
                                .foregroundStyle(.primary)
                            HStack(spacing: 4) {
                                Text(account.kind.title)
                                if account.isArchived {
                                    Text("已归档")
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color(uiColor: .tertiarySystemFill))
                                        .clipShape(Capsule())
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Money.string(fromCents: LedgerService.balanceCents(of: account, transactions: transactions)))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(
                                LedgerService.balanceCents(of: account, transactions: transactions) < 0
                                    ? Theme.alert : .primary
                            )
                    }
                    .opacity(account.isArchived ? 0.55 : 1)
                }
            }

            Section {
                Button {
                    adding = true
                } label: {
                    Label("添加账户", systemImage: "plus.circle")
                }
            } footer: {
                Text("有流水的账户不能删除，只能归档；信用卡消费后余额显示为负数（欠款）")
            }
        }
        .navigationTitle("账户管理")
        .sheet(isPresented: $adding) {
            AccountEditorView(account: nil)
        }
    }
}

/// 账户编辑器（新建/编辑共用）
struct AccountEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    private let existing: Account?

    @State private var name = ""
    @State private var kind: AccountKind = .cash
    @State private var icon = "banknote"
    @State private var colorHex = "4A90D9"
    @State private var balanceText = ""
    @State private var creditLimitText = ""
    @State private var billingDay = 1
    @State private var dueDay = 1
    @State private var isArchived = false
    @State private var didLoad = false

    init(account: Account?) {
        self.existing = account
    }

    private let iconOptions = ["banknote", "creditcard", "building.columns", "qrcode", "message",
                               "car", "house", "gift", "cart", "gamecontroller"]

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("账户名称", text: $name)
                    Picker("类型", selection: $kind) {
                        ForEach(AccountKind.allCases) { k in
                            Text(k.title).tag(k)
                        }
                    }
                    .onChange(of: kind) { _, newKind in
                        icon = newKind.defaultIcon
                    }
                    iconRow
                    colorRow
                }

                Section(kind.isCredit ? "期初欠款（元）" : "期初余额（元）") {
                    TextField("0.00", text: $balanceText)
                        .keyboardType(.decimalPad)
                        .monospacedDigit()
                }

                if kind.isCredit {
                    Section("信用卡") {
                        TextField("信用额度（元）", text: $creditLimitText)
                            .keyboardType(.decimalPad)
                            .monospacedDigit()
                        Stepper("账单日 \(billingDay) 号", value: $billingDay, in: 1...31)
                        Stepper("还款日 \(dueDay) 号", value: $dueDay, in: 1...31)
                    }
                }

                if existing != nil {
                    Section {
                        Toggle("归档（不再出现在选择器）", isOn: $isArchived)
                    }
                }
            }
            .navigationTitle(existing == nil ? "添加账户" : "编辑账户")
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
            .onAppear(perform: load)
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var iconRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(iconOptions, id: \.self) { option in
                    Button {
                        icon = option
                    } label: {
                        Image(systemName: option)
                            .font(.system(size: 15))
                            .frame(width: 36, height: 36)
                            .background(icon == option ? Color.accentColor.opacity(0.15) : Color(uiColor: .tertiarySystemFill))
                            .foregroundStyle(icon == option ? Color.accentColor : .secondary)
                            .clipShape(Circle())
                            .overlay {
                                if icon == option {
                                    Circle().stroke(Color.accentColor, lineWidth: 1.5)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var colorRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Theme.palette, id: \.self) { hex in
                    Button {
                        colorHex = hex
                    } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 28, height: 28)
                            .overlay {
                                if colorHex == hex {
                                    Circle().stroke(.primary, lineWidth: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let account = existing else { return }
        name = account.name
        kind = account.kind
        icon = account.icon
        colorHex = account.colorHex
        balanceText = account.initialBalanceCents == 0
            ? ""
            : Money.inputString(fromCents: account.initialBalanceCents)
        creditLimitText = account.creditLimitCents == 0
            ? ""
            : Money.inputString(fromCents: account.creditLimitCents)
        billingDay = account.billingDay
        dueDay = account.dueDay
        isArchived = account.isArchived
    }

    private func save() {
        guard canSave else { return }
        let balanceCents = Money.cents(fromString: balanceText) ?? 0
        let limitCents = Money.cents(fromString: creditLimitText) ?? 0

        if let account = existing {
            account.name = name
            account.kindRaw = kind.rawValue
            account.icon = icon
            account.colorHex = colorHex
            account.initialBalanceCents = balanceCents
            account.creditLimitCents = kind.isCredit ? limitCents : 0
            account.billingDay = billingDay
            account.dueDay = dueDay
            account.isArchived = isArchived
        } else {
            let maxOrder = accounts.map { $0.sortOrder }.max() ?? -1
            context.insert(Account(name: name,
                                   kind: kind,
                                   icon: icon,
                                   colorHex: colorHex,
                                   initialBalanceCents: balanceCents,
                                   creditLimitCents: kind.isCredit ? limitCents : 0,
                                   billingDay: billingDay,
                                   dueDay: dueDay,
                                   sortOrder: maxOrder + 1))
        }
        try? context.save()
        dismiss()
    }
}
