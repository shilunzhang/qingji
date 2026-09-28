import SwiftUI
import SwiftData
import UIKit

/// 相册扫描记账（文档 F-13，Tier 2）：增量扫描新截图 → 批量确认入账
struct AlbumScanView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    /// v1.4.2：重复提示需要查询历史账目
    @Query private var transactions: [Transaction]
    @StateObject private var model = AlbumScanModel.shared

    @State private var authorized = false
    @State private var categoryTarget: CategoryTarget?

    /// sheet(item:) 要求 Identifiable 的包装类型
    private struct CategoryTarget: Identifiable {
        let draftID: String
        var id: String { draftID }
    }

    var body: some View {
        List {
            permissionSection
            scanSection
            ForEach($model.drafts) { $draft in
                draftSection($draft)
            }
        }
        .navigationTitle("相册扫描记账")
        .onAppear {
            authorized = PhotoScanService.isAuthorized
        }
        .task {
            if authorized, model.drafts.isEmpty {
                await model.scanIfAuthorized()
            }
        }
        .sheet(item: $categoryTarget) { target in
            CategoryPickerSheet(selected: nil, defaultKind: .expense) { picked in
                if let index = model.drafts.firstIndex(where: { $0.id == target.draftID }) {
                    model.drafts[index].category = picked
                }
            }
        }
    }

    // MARK: - 权限引导（AC3）

    @ViewBuilder
    private var permissionSection: some View {
        if !authorized {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("需要照片权限", systemImage: "photo.badge.exclamationmark")
                        .font(.headline)
                    Text("轻记只读取你主动截取的「屏幕快照」用于识别支付金额，全部在本机处理，不会上传。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("去系统设置开启") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private var scanSection: some View {
        Section {
            Button {
                Task {
                    if !authorized {
                        authorized = await PhotoScanService.requestAccess()
                    }
                    if authorized {
                        await model.scan()
                    }
                }
            } label: {
                if model.isScanning {
                    HStack {
                        ProgressView()
                        Text("识别中…")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Label(authorized ? "扫描相册新截图" : "允许访问照片并扫描", systemImage: "arrow.clockwise")
                }
            }
            .disabled(model.isScanning)

            if let text = model.lastScanText {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("扫描最近 10 张屏幕快照，账单列表页会按行拆成多笔；非账单页自动跳过并标记已处理")
        }
    }

    // MARK: - 草稿卡片

    private func draftSection(_ draft: Binding<AlbumScanDraft>) -> some View {
        Section {
            Picker("类型", selection: draft.kind) {
                Text("支出").tag(TxKind.expense)
                Text("收入").tag(TxKind.income)
            }
            .pickerStyle(.segmented)
            TextField("金额（元）", text: draft.amountText)
                .keyboardType(.decimalPad)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    discardSwipe(draft.wrappedValue)
                }
            DatePicker("时间", selection: draft.date)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    discardSwipe(draft.wrappedValue)
                }
            TextField("收款方/商户", text: draft.counterparty)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    discardSwipe(draft.wrappedValue)
                }
            TextField("备注", text: draft.note)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    discardSwipe(draft.wrappedValue)
                }
            if let channel = draft.wrappedValue.channel {
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
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    discardSwipe(draft.wrappedValue)
                }
            }
            HStack {
                Text("账户")
                Spacer()
                Menu(draft.wrappedValue.account?.name ?? "请选择") {
                    ForEach(activeAccounts) { account in
                        Button(account.name) {
                            draft.wrappedValue.account = account
                        }
                    }
                }
                .foregroundStyle(draft.wrappedValue.account == nil ? Color.orange : Color.primary)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                discardSwipe(draft.wrappedValue)
            }
            HStack {
                Text("分类")
                Spacer()
                Button(draft.wrappedValue.category?.name ?? "未分类") {
                    categoryTarget = CategoryTarget(draftID: draft.wrappedValue.id)
                }
                .foregroundStyle(draft.wrappedValue.category == nil ? .secondary : .primary)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                discardSwipe(draft.wrappedValue)
            }
            if let dup = duplicateHint(for: draft.wrappedValue) {
                Label("疑似与已有账目重复：\(dup.summary)", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(Theme.alert)
            }
            if !draft.wrappedValue.warning.isEmpty {
                Label(draft.wrappedValue.warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Theme.alert)
            }
            HStack {
                Button {
                    model.ignore(draft.wrappedValue)
                } label: {
                    Text("忽略")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    save(draft.wrappedValue)
                } label: {
                    Text("入账")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave(draft.wrappedValue))
            }
        }
    }

    // MARK: - v1.4.2 重复提示与左滑丢弃

    /// 左滑丢弃草稿：等同「忽略」（登记已处理，下次扫描不再弹出）
    @ViewBuilder
    private func discardSwipe(_ draft: AlbumScanDraft) -> some View {
        Button(role: .destructive) {
            withAnimation { model.ignore(draft) }
        } label: {
            Label("丢弃", systemImage: "trash")
        }
    }

    /// F-14 预检提示：与历史账目同向同额且时间差 ≤ 窗口 → 草稿卡片上黄字提醒。
    /// 入账时仍会走自动闸门（疑似重复会记日志跳过）
    private func duplicateHint(for draft: AlbumScanDraft) -> DuplicateMatch? {
        guard DuplicateGuard.sensitivity != .off else { return nil }
        guard let cents = Money.cents(fromString: draft.amountText), cents > 0 else { return nil }
        return DuplicateGuard.findDuplicate(of: draft.kind, amountCents: cents,
                                            date: draft.date, in: transactions)
    }

    private var activeAccounts: [Account] {
        accounts.filter { !$0.isArchived }
    }

    private func canSave(_ draft: AlbumScanDraft) -> Bool {
        guard let cents = Money.cents(fromString: draft.amountText), cents > 0 else { return false }
        return draft.account != nil || !activeAccounts.isEmpty
    }

    private func save(_ draft: AlbumScanDraft) {
        model.commit(draft, context: context, accounts: activeAccounts)
    }
}
