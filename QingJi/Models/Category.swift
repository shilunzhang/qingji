import Foundation
import SwiftData

/// 分类方向
enum CategoryKind: String, Codable, CaseIterable, Identifiable {
    case expense, income
    var id: String { rawValue }
    var title: String { self == .expense ? "支出" : "收入" }
}

/// 两级分类（文档 §4.3）。系统分类不可删除。
@Model
final class Category {
    var id: UUID = UUID()
    var name: String = ""
    /// CategoryKind.rawValue
    var kindRaw: String = CategoryKind.expense.rawValue
    /// SF Symbol 名
    var icon: String = "ellipsis"
    var colorHex: String = "9E9E9E"
    var sortOrder: Int = 0
    /// 内置分类不可删除
    var isSystem: Bool = false

    @Relationship(inverse: \Category.children) var parent: Category? = nil
    @Relationship var children: [Category]? = nil

    var kind: CategoryKind { CategoryKind(rawValue: kindRaw) ?? .expense }
    /// 排序用：先父后子，子分类跟随父分类排序
    var displayName: String { parent == nil ? name : "\(parent?.name ?? "")·\(name)" }

    init(name: String,
         kind: CategoryKind,
         icon: String = "ellipsis",
         colorHex: String = "9E9E9E",
         sortOrder: Int = 0,
         isSystem: Bool = false,
         parent: Category? = nil) {
        self.name = name
        self.kindRaw = kind.rawValue
        self.icon = icon
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.isSystem = isSystem
        self.parent = parent
    }

    /// 一级分类的可选子分类（已排序）
    var sortedChildren: [Category] {
        (children ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }
}
