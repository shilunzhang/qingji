import SwiftUI
import SwiftData

/// 全部分类选择（文档 F-03）：支出/收入分段 + 父子两级
struct CategoryPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @State private var kind: CategoryKind
    private let selectedID: UUID?
    private let onSelect: (Category) -> Void

    init(selected: Category?, defaultKind: CategoryKind, onSelect: @escaping (Category) -> Void) {
        _kind = State(initialValue: selected?.kind ?? defaultKind)
        self.selectedID = selected?.id
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(parents) { parent in
                    Section {
                        selectableRow(parent)
                        ForEach(parent.sortedChildren) { child in
                            selectableRow(child)
                        }
                    }
                }
                if parents.isEmpty {
                    EmptyStateView(icon: "square.grid.2x2",
                                   title: "暂无分类",
                                   hint: "可在「我的 → 分类管理」中添加")
                }
            }
            .navigationTitle("选择分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .safeAreaInset(edge: .top) {
                Picker("方向", selection: $kind) {
                    ForEach(CategoryKind.allCases) { k in
                        Text(k.title).tag(k)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 6)
                .background(Color(uiColor: .systemGroupedBackground))
            }
        }
    }

    private var parents: [Category] {
        categories.filter { $0.parent == nil && $0.kindRaw == kind.rawValue }
    }

    private func selectableRow(_ category: Category) -> some View {
        Button {
            onSelect(category)
            dismiss()
        } label: {
            HStack {
                IconBadge(icon: category.icon, colorHex: category.colorHex, size: 32)
                Text(category.name)
                Spacer()
                if selectedID == category.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
