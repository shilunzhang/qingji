import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// 记账页（文档 F-01）：支出/收入/转账 + 自定义键盘 + 分类/账户选择 + 备注凭证
struct AddTransactionView: View {
    enum Mode {
        /// 预填数据（供 OCR/自动化入口复用记账页）
        struct Prefill {
            var amountCents: Int64? = nil
            var date: Date? = nil
            var note: String? = nil
            var categoryID: UUID? = nil
        }

        case create(TxKind, Prefill?)
        case edit(Transaction)
    }

    let mode: Mode

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \Transaction.date, order: .reverse) private var history: [Transaction]

    @State private var kind: TxKind = .expense
    @State private var amountText = ""
    @State private var selectedCategory: Category?
    @State private var account: Account?
    @State private var toAccount: Account?
    @State private var date = Date()
    @State private var note = ""
    @State private var newPhotoData: [Data] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showCategorySheet = false
    @State private var showAccountPicker = false
    @State private var showToAccountPicker = false
    @State private var didSetup = false
    @State private var pendingDuplicate: DuplicateMatch?
    @State private var showDuplicateConfirm = false
    @State private var duplicateBlockMessage: String?

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var amountCents: Int64? { Money.cents(fromString: amountText) }

    private var canSave: Bool {
        guard let cents = amountCents, cents > 0 else { return false }
        guard account != nil else { return false }
        if kind == .transfer {
            guard let to = toAccount, to.id != account?.id else { return false }
        }
        return true
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    kindPicker
                    amountDisplay
                    if kind == .transfer {
                        transferSection
                    } else {
                        categorySection
                        accountSection
                    }
                    metaSection
                    photoSection
                }
                .padding(.vertical, 12)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    clearButton
                    NumberPad(onDigit: handleDigit, onDelete: handleDelete)
                }
                .padding(.top, 10)
                .background(Color(uiColor: .systemGroupedBackground))
            }
            .navigationTitle(isEditing ? "编辑账目" : "记一笔")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showCategorySheet) {
                CategoryPickerSheet(selected: selectedCategory, defaultKind: categoryKind) { picked in
                    selectedCategory = picked
                }
            }
            .sheet(isPresented: $showAccountPicker) {
                AccountPickerSheet(title: "选择账户", selected: account) { picked in
                    if toAccount?.id == picked.id { toAccount = nil }
                    account = picked
                }
            }
            .sheet(isPresented: $showToAccountPicker) {
                AccountPickerSheet(title: "转入账户", selected: toAccount, excluding: account) { picked in
                    toAccount = picked
                }
            }
            .alert("疑似重复账目", isPresented: $showDuplicateConfirm) {
                Button("仍要保存") {
                    if let cents = amountCents, cents > 0, let account {
                        commit(cents: cents, account: account)
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text(pendingDuplicate.map { "已有一笔 \($0.summary)，确认仍要保存这笔吗？" } ?? "")
            }
            .alert("无法保存", isPresented: Binding(
                get: { duplicateBlockMessage != nil },
                set: { if !$0 { duplicateBlockMessage = nil } }
            )) {
                Button("好的", role: .cancel) {}
            } message: {
                Text(duplicateBlockMessage ?? "")
            }
            .onChange(of: photoItems.count) { _, _ in
                if !photoItems.isEmpty {
                    importPhotos(photoItems)
                }
            }
            .onAppear(perform: setup)
        }
    }

    // MARK: - 子视图

    private var kindPicker: some View {
        Picker("类型", selection: $kind) {
            ForEach([TxKind.expense, .income, .transfer]) { k in
                Text(k.title).tag(k)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .onChange(of: kind) { _, newKind in
            if newKind == .transfer {
                selectedCategory = nil
            } else {
                selectedCategory = CategoryPredictor.topCategory(
                    categories: categories, transactions: history, kind: newKind, at: date)
            }
        }
    }

    private var amountDisplay: some View {
        VStack(spacing: 4) {
            Text("金额")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("¥")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(displayAmount)
                    .font(.system(size: 44, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                Spacer()
                Button {
                    amountText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .opacity(amountText.isEmpty ? 0 : 1)
            }
        }
        .card()
        .padding(.horizontal, 16)
    }

    private var displayAmount: String {
        guard let cents = amountCents else { return "0.00" }
        return Money.inputString(fromCents: cents)
    }

    private var clearButton: some View {
        Button {
            amountText = ""
        } label: {
            Text("清空")
                .font(.footnote)
        }
        .opacity(amountText.isEmpty ? 0 : 1)
    }

    private var categoryKind: CategoryKind {
        kind == .income ? .income : .expense
    }

    /// 快捷分类宫格：预测排序前 7 + 「全部」入口
    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("分类")
                .font(.caption)
                .foregroundStyle(.secondary)
            let ranked = CategoryPredictor.ranked(
                categories: categories, transactions: history, kind: kind, at: date)
            let quick = Array(ranked.prefix(7))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                ForEach(quick) { category in
                    categoryCell(category)
                }
                if quick.count < 7 {
                    ForEach(0..<(7 - quick.count), id: \.self) { _ in
                        Color.clear.frame(height: 52)
                    }
                }
                allCategoriesCell
            }
        }
        .card()
        .padding(.horizontal, 16)
    }

    private func categoryCell(_ category: Category) -> some View {
        Button {
            selectedCategory = category
        } label: {
            VStack(spacing: 4) {
                IconBadge(icon: category.icon, colorHex: category.colorHex, size: 34)
                Text(category.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.vertical, 4)
            .background(selectedCategory?.id == category.id ? Color.accentColor.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var allCategoriesCell: some View {
        Button {
            showCategorySheet = true
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 17))
                    .frame(width: 34, height: 34)
                    .background(Color(uiColor: .tertiarySystemFill))
                    .clipShape(Circle())
                Text("全部")
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    private var accountSection: some View {
        VStack(spacing: 0) {
            pickerRow(label: "账户", value: account?.name ?? "请选择", showChevron: true) {
                showAccountPicker = true
            }
        }
        .card()
        .padding(.horizontal, 16)
    }

    private var transferSection: some View {
        VStack(spacing: 0) {
            pickerRow(label: "转出账户", value: account?.name ?? "请选择", showChevron: true) {
                showAccountPicker = true
            }
            Divider().padding(.leading, 12)
            pickerRow(label: "转入账户", value: toAccount?.name ?? "请选择", showChevron: true) {
                showToAccountPicker = true
            }
        }
        .card()
        .padding(.horizontal, 16)
    }

    private var metaSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("日期")
                Spacer()
                DatePicker("", selection: $date)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "zh_CN"))
            }
            .padding(.vertical, 8)
            Divider().padding(.leading, 12)
            HStack {
                Text("备注")
                TextField("点击填写备注", text: $note)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 8)
        }
        .font(.subheadline)
        .card()
        .padding(.horizontal, 16)
    }

    private func pickerRow(label: String, value: String, showChevron: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                Spacer()
                Text(value)
                    .foregroundStyle(value == "请选择" ? .tertiary : .primary)
                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.subheadline)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 凭证图

    private var currentPhotoCount: Int { existingCount + newPhotoData.count }

    private var existingCount: Int {
        if case .edit(let tx) = mode { return tx.attachments?.count ?? 0 }
        return 0
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("凭证（最多 3 张）")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                if case .edit(let tx) = mode {
                    ForEach(tx.attachments ?? []) { attachment in
                        if let image = UIImage(data: attachment.data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                ForEach(newPhotoData.indices, id: \.self) { index in
                    if let image = UIImage(data: newPhotoData[index]) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    newPhotoData.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white, .secondary)
                                }
                                .offset(x: 6, y: -6)
                            }
                    }
                }
                if currentPhotoCount < 3 {
                    PhotosPicker(selection: $photoItems,
                                 maxSelectionCount: 3 - currentPhotoCount,
                                 matching: .images) {
                        Image(systemName: "camera")
                            .font(.title3)
                            .frame(width: 64, height: 64)
                            .background(Color(uiColor: .tertiarySystemFill))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .card()
        .padding(.horizontal, 16)
    }

    private func importPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        let room = 3 - currentPhotoCount
        Task {
            var imported: [Data] = []
            for item in items.prefix(max(0, room)) {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let compressed = Self.compress(imageData: data) {
                    imported.append(compressed)
                }
            }
            await MainActor.run {
                newPhotoData.append(contentsOf: imported)
                photoItems = []
            }
        }
    }

    /// 压缩到长边 ≤1200px 的 JPEG（文档 §8）
    static func compress(imageData data: Data, maxDimension: CGFloat = 1200) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let longest = max(size.width, size.height)
        var result = image
        if longest > maxDimension {
            let scale = maxDimension / longest
            let newSize = CGSize(width: size.width * scale, height: size.height * scale)
            UIGraphicsBeginImageContextWithOptions(newSize, true, 1)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            if let resized = UIGraphicsGetImageFromCurrentImageContext() {
                result = resized
            }
            UIGraphicsEndImageContext()
        }
        return result.jpegData(compressionQuality: 0.6)
    }

    // MARK: - 键盘输入

    private func handleDigit(_ digit: String) {
        if digit == "." {
            guard !amountText.contains(".") else { return }
            amountText = amountText.isEmpty ? "0." : amountText + "."
            return
        }
        if amountText.isEmpty { amountText = digit; return }
        if let dotIndex = amountText.firstIndex(of: ".") {
            let decimals = amountText.distance(from: amountText.index(after: dotIndex), to: amountText.endIndex)
            guard decimals < 2 else { return }
            amountText.append(Character(digit))
        } else {
            guard amountText.count < 9 else { return }
            amountText = amountText == "0" ? digit : amountText + digit
        }
    }

    private func handleDelete() {
        guard !amountText.isEmpty else { return }
        amountText.removeLast()
    }

    // MARK: - 装配与保存

    private func setup() {
        guard !didSetup else { return }
        didSetup = true
        switch mode {
        case .create(let initialKind, let prefill):
            kind = initialKind
            account = accounts.first { !$0.isArchived }
            selectedCategory = CategoryPredictor.topCategory(
                categories: categories, transactions: history, kind: initialKind, at: Date())
            if let prefill {
                if let cents = prefill.amountCents { amountText = Money.inputString(fromCents: cents) }
                if let prefillDate = prefill.date { date = prefillDate }
                if let prefillNote = prefill.note { note = prefillNote }
                if let categoryID = prefill.categoryID {
                    selectedCategory = categories.first { $0.id == categoryID }
                }
            }
        case .edit(let tx):
            kind = tx.type
            amountText = Money.inputString(fromCents: tx.amountCents)
            selectedCategory = tx.category
            account = tx.account
            toAccount = tx.toAccount
            date = tx.date
            note = tx.note
        }
    }

    /// 保存：先过 F-14 防重闸门（编辑时排除自身），再落库
    private func save() {
        guard let cents = amountCents, cents > 0, let account else { return }
        var excludeID: UUID?
        if case .edit(let editing) = mode { excludeID = editing.id }

        let match = DuplicateGuard.findDuplicate(of: kind,
                                                 amountCents: cents,
                                                 date: date,
                                                 in: history,
                                                 excludeID: excludeID)
        switch DuplicateGuard.manualDecision(for: match) {
        case .allow:
            commit(cents: cents, account: account)
        case .confirm(let duplicated):
            pendingDuplicate = duplicated
            showDuplicateConfirm = true
        case .block(let duplicated):
            duplicateBlockMessage = "已存在 \($0.summary)。当前防重策略为「阻止」，如确需保存请在「我的 → 自动记账」中调整灵敏度。"
        }
    }

    private func commit(cents: Int64, account: Account) {
        let effectiveToAccount = kind == .transfer ? toAccount : nil
        let effectiveCategory = kind == .transfer ? nil : selectedCategory
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        switch mode {
        case .create:
            let tx = Transaction(kind: kind,
                                 amountCents: cents,
                                 date: date,
                                 account: account,
                                 toAccount: effectiveToAccount,
                                 category: effectiveCategory,
                                 note: trimmedNote)
            context.insert(tx)
            attachPhotos(to: tx)
        case .edit(let tx):
            tx.kind = kind.rawValue
            tx.amountCents = cents
            tx.date = date
            tx.note = trimmedNote
            tx.account = account
            tx.toAccount = effectiveToAccount
            tx.category = effectiveCategory
            tx.updatedAt = Date.now
            attachPhotos(to: tx)
        }
        try? context.save()
        dismiss()
    }

    private func attachPhotos(to tx: Transaction) {
        for data in newPhotoData {
            let attachment = Attachment(data: data)
            attachment.transaction = tx
            context.insert(attachment)
        }
        newPhotoData = []
    }
}
