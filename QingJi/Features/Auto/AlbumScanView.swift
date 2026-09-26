import SwiftUI
import SwiftData
import UIKit

/// 相册扫描记账（文档 F-13，Tier 2）：增量扫描新截图 → 批量确认入账
struct AlbumScanView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @ObservedObject private var model = AlbumScanModel.shared

    @State private var authorized = PhotoScanService.isAuthorized
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
                Task { await model.scan() }
            } label: {
                if model.isScanning {
                    HStack {
                        ProgressView()
                        Text("识别中…")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Label("扫描相册新截图", systemImage: "arrow.clockwise")
                }
            }
            .disabled(!authorized || model.isScanning)

            if let text = model.lastScanText {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("扫描最近 10 张屏幕快照；非支付页面会自动跳过并标记已处理，不会重复弹出")
        }
    }

    // MARK: - 草稿卡片

    private func draftSection(_ draft: Binding<AlbumScanDraft>) -> some View {
        Section {
            TextField("金额（元）", text: draft.amountText)
                .keyboardType(.decimalPad)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            DatePicker("时间", selection: draft.date)
            TextField("收款方/备注", text: draft.counterparty)
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
            HStack {
                Text("分类")
                Spacer()
                Button(draft.wrappedValue.category?.name ?? "未分类") {
                    categoryTarget = CategoryTarget(draftID: draft.wrappedValue.id)
                }
                .foregroundStyle(draft.wrappedValue.category == nil ? .secondary : .primary)
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

    private var activeAccounts: [Account] {
        accounts.filter { !$0.isArchived }
    }

    private func canSave(_ draft: AlbumScanDraft) -> Bool {
        guard let cents = Money.cents(fromString: draft.amountText), cents > 0 else { return false }
        return draft.account != nil || !activeAccounts.isEmpty
    }

    private func save(_ draft: AlbumScanDraft) {
        let fallback = activeAccounts.first
        model.commit(draft, context: context, fallbackAccount: fallback)
    }
}
