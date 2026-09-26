import SwiftUI
import SwiftData

/// 分类管理（文档 F-03）：系统分类不可删；自定义分类可增改删
struct CategoryManageView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @State private var kind: CategoryKind = .expense
    @State private var addingParent = false
    @State private var childTarget: Category?      // 为该父分类添加子分类
    @State private var editing: Category?

    private var parents: [Category] {
        categories.filter { $0.parent == nil && $0.kindRaw == kind.rawValue }
    }

    var body: some View {
        List {
            Section {
                Picker("方向", selection: $kind) {
                    ForEach(CategoryKind.allCases) { k in
                        Text(k.title).tag(k)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }

            ForEach(parents) { parent in
                Section {
                    DisclosureGroup {
                        ForEach(parent.sortedChildren) { child in
                            Button {
                                editing = child
                            } label: {
                                categoryRow(child)
                            }
                            .buttonStyle(.plain)
                        }
                        Button {
                            childTarget = parent
                        } label: {
                            Label("添加子分类", systemImage: "plus.circle")
                                .font(.subheadline)
                        }
                    } label: {
                        Button {
                            editing = parent
                        } label: {
                            HStack {
                                categoryRow(parent)
                                Spacer()
                                Text("\(parent.sortedChildren.count) 个子分类")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("分类管理")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    addingParent = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $addingParent) {
            CategoryEditorView(category: nil, parent: nil, defaultKind: kind)
        }
        .sheet(item: $childTarget) { parent in
            CategoryEditorView(category: nil, parent: parent, defaultKind: parent.kind)
        }
        .sheet(item: $editing) { category in
            CategoryEditorView(category: category, parent: nil, defaultKind: category.kind)
        }
    }

    private func categoryRow(_ category: Category) -> some View {
        HStack {
            IconBadge(icon: category.icon, colorHex: category.colorHex, size: 32)
            Text(category.name)
                .foregroundStyle(.primary)
            if category.isSystem {
                Text("内置")
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color(uiColor: .tertiarySystemFill))
                    .clipShape(Capsule())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

/// 分类编辑器：category != nil 编辑；否则新建（parent 可指定为子分类）
struct CategoryEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private let existing: Category?
    private let parent: Category?

    @State private var name = ""
    @State private var kind: CategoryKind = .expense
    @State private var icon = "ellipsis"
    @State private var colorHex = "9E9E9E"
    @State private var didLoad = false

    init(category: Category?, parent: Category?, defaultKind: CategoryKind) {
        self.existing = category
        self.parent = parent
        _kind = State(initialValue: category?.kind ?? parent?.kind ?? defaultKind)
    }

    private let iconOptions = ["fork.knife", "bus", "bag", "house", "gamecontroller", "cross.case",
                               "book", "phone", "gift", "pawprint", "airplane", "banknote",
                               "rosette", "chart.line.uptrend.xyaxis", "briefcase", "doc.text", "ellipsis"]

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("分类名称", text: $name)
                }
                if existing == nil && parent == nil {
                    Section("方向") {
                        Picker("方向", selection: $kind) {
                            ForEach(CategoryKind.allCases) { k in
                                Text(k.title).tag(k)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                Section("图标与颜色") {
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

                if let existing, !existing.isSystem, (existing.children ?? []).isEmpty {
                    Section {
                        Button("删除分类", role: .destructive) {
                            context.delete(existing)
                            try? context.save()
                            dismiss()
                        }
                    } footer: {
                        Text("删除后该分类下的账目将显示为「未分类」")
                    }
                } else if let existing, existing.isSystem {
                    Section {
                    } footer: {
                        Text("内置分类不能删除，可修改名称与图标")
                    }
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
            .onAppear(perform: load)
        }
    }

    private var title: String {
        if existing != nil { return parent != nil ? "编辑子分类" : "编辑分类" }
        return parent != nil ? "添加子分类" : "添加分类"
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let category = existing else {
            if colorHex == "9E9E9E" {
                colorHex = Theme.palette.randomElement() ?? "9E9E9E"
            }
            return
        }
        name = category.name
        icon = category.icon
        colorHex = category.colorHex
    }

    private func save() {
        guard canSave else { return }
        if let category = existing {
            category.name = name
            category.icon = icon
            category.colorHex = colorHex
        } else {
            let sortOrder: Int
            if let parent {
                sortOrder = (parent.children ?? []).count
            } else {
                let siblings = (try? context.fetch(FetchDescriptor<Category>()))?
                    .filter { $0.parent == nil && $0.kindRaw == kind.rawValue } ?? []
                sortOrder = siblings.count
            }
            context.insert(Category(name: name,
                                    kind: kind,
                                    icon: icon,
                                    colorHex: colorHex,
                                    sortOrder: sortOrder,
                                    isSystem: false,
                                    parent: parent))
        }
        try? context.save()
        dismiss()
    }
}
