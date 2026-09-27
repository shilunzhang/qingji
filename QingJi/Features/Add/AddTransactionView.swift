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
    @State private var originalText = ""
    @State private var showCamera = false
    @State private var hintMessage: String?
    @State private var pendingDuplicate: DuplicateMatch?
    @State private var pendingOriginalCents: Int64 = 0
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
            formContent
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
        .sheet(isPresented: $showCamera) {
            CameraPicker { image in
                handleCapturedImage(image)
            }
            .ignoresSafeArea()
        }
        .duplicateAlerts
        .onChange(of: photoItems.count) { _, _ in
            if !photoItems.isEmpty {
                importPhotos(photoItems)
            }
        }
        .onAppear(perform: setup)
    }

    /// 表单主体（拆分子表达式，避免 ViewBuilder 类型检查超时）
    private var formContent: some View {
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
        .navigationTitle(navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
    }

    private var navigationTitleText: String {
        isEditing ? "编辑账目" : "记一笔"
    }

    private var bottomAccessory: some View {
        VStack(spacing: 10) {
            clearButton
            NumberPad(onDigit: handleDigit, onDelete: handleDelete)
        }
        .padding(.top, 10)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("取消") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showCamera = true
            } label: {
                Image(systemName: "camera.viewfinder")
            }
            .accessibilityLabel("拍照识别")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("保存") { save() }
                .fontWeight(.semibold)
                .disabled(!canSave)
        }
    }

    /// 防重与提示弹窗组
    private var duplicateAlerts: some View {
        alertsGroup
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
            amountLabel
            amountMainRow
            originalPriceRow
        }
        .card()
        .padding(.horizontal, 16)
    }

    private var amountLabel: some View {
        Text("金额")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var amountMainRow: some View {
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
            clearAmountButton
        }
    }

    private var clearAmountButton: some View {
        Button {
            amountText = ""
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.tertiary)
        }
        .opacity(amountText.isEmpty ? 0.0 : 1.0)
    }

    private var originalPriceRow: some View {
        HStack(spacing: 6) {
            Text("原价")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("选填，有优惠时填写", text: $originalText)
                .keyboardType(.decimalPad)
                .font(.caption)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
            savingsText
        }
    }

    /// 实付小于原价时显示「省 ¥X」
    private var savingsText: Text? {
        guard let original = Money.cents(fromString: originalText),
              let cents = amountCents,
              original > cents else { return nil }
        let saved = Money.string(fromCents: original - cents)
        return Text("省 \(saved)")
            .font(.caption2.weight(.medium))
            .foregroundStyle(Theme.income)
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

    private var duplicateAlerts: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .alert("疑似重复账目", isPresented: $showDuplicateConfirm) {
            Button("仍要保存") {
                if let cents = amountCents, cents > 0, let account {
                    commit(cents: cents, account: account, originalCents: pendingOriginalCents)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(pendingDuplicate.map { "已有一笔 \($0.summary)，确认仍要保存这笔吗？" } ?? "")
        }
        alert("无法保存", isPresented: Binding(
            get: { duplicateBlockMessage != nil },
            set: { if !$0 { duplicateBlockMessage = nil } }
        )) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(duplicateBlockMessage ?? "")
        }
        alert("提示", isPresented: Binding(
            get: { hintMessage != nil },
            set: { if !$0 { hintMessage = nil } }
        )) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(hintMessage ?? "")
        }
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
            originalText = tx.originalAmountCents > 0 ? Money.inputString(fromCents: tx.originalAmountCents) : ""
        }
    }

    /// 拍照识别（F-15）：智能抽取后填入第一笔，多笔提示走「截图记账」
    private func handleCapturedImage(_ image: UIImage) {
        Task {
            let rows = await SmartExtractionService.extractRows(from: image)
            await MainActor.run {
                guard let first = rows.first, let cents = first.amountCents, cents > 0 else {
                    hintMessage = "未识别出支付信息，请手动填写"
                    return
                }
                amountText = Money.inputString(fromCents: cents)
                if let extractedDate = first.date { date = extractedDate }
                if let extractedKind = first.kind { kind = extractedKind }
                if let extractedNote = first.note, !extractedNote.isEmpty {
                    note = extractedNote
                } else if let merchant = first.counterparty, !merchant.isEmpty {
                    note = merchant
                }
                if rows.count > 1 {
                    hintMessage = "识别到 \(rows.count) 笔，已填入第一笔；其余请用「截图记账」处理"
                }
            }
        }
    }

    /// 保存：先过 F-14 防重闸门（编辑时排除自身），再落库
    private func save() {
        guard let cents = amountCents, cents > 0, let account else { return }
        var excludeID: UUID?
        if case .edit(let editing) = mode { excludeID = editing.id }
        let original = Money.cents(fromString: originalText) ?? 0

        let match = DuplicateGuard.findDuplicate(of: kind,
                                                 amountCents: cents,
                                                 date: date,
                                                 in: history,
                                                 excludeID: excludeID)
        switch DuplicateGuard.manualDecision(for: match) {
        case .allow:
            commit(cents: cents, account: account, originalCents: original)
        case .confirm(let duplicated):
            pendingOriginalCents = original
            pendingDuplicate = duplicated
            showDuplicateConfirm = true
        case .block(let duplicated):
            duplicateBlockMessage = "已存在 \(duplicated.summary)。当前防重策略为「阻止」，如确需保存请在「我的 → 自动记账」中调整灵敏度。"
        }
    }

    private func commit(cents: Int64, account: Account, originalCents: Int64) {
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
                                 note: trimmedNote,
                                 originalAmountCents: originalCents)
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
            tx.originalAmountCents = originalCents
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
