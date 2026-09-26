import SwiftUI
import SwiftData

/// 账户选择（文档 F-02）：跳过归档账户，可排除一个（转账的另一端）
struct AccountPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    private let title: String
    private let selectedID: UUID?
    private let excludeID: UUID?
    private let onSelect: (Account) -> Void

    init(title: String, selected: Account?, excluding: Account? = nil, onSelect: @escaping (Account) -> Void) {
        self.title = title
        self.selectedID = selected?.id
        self.excludeID = excluding?.id
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(availableAccounts) { account in
                    Button {
                        onSelect(account)
                        dismiss()
                    } label: {
                        HStack {
                            IconBadge(icon: account.icon, colorHex: account.colorHex, size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.name)
                                Text(account.kind.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedID == account.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                if availableAccounts.isEmpty {
                    EmptyStateView(icon: "creditcard",
                                   title: "暂无可用账户",
                                   hint: "可在「我的 → 账户管理」中添加")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var availableAccounts: [Account] {
        accounts.filter { !$0.isArchived && $0.id != excludeID }
    }
}
