import Foundation
import SwiftData

/// 首次启动种子数据（文档 F-00/附录 A、B）。幂等：以 UserDefaults 标记 + 系统分类存在性双重保护
/// （应对重装后 iCloud 数据先于标记到达的情况）。
enum SeedService {

    private static let seedFlagKey = "qingji.didSeed"

    struct SeedCategory {
        let name: String
        let icon: String
        let colorHex: String
        var children: [(String, String)] = []
    }

    static let expenseCategories: [SeedCategory] = [
        .init(name: "餐饮", icon: "fork.knife", colorHex: "FF8A3D",
              children: [("早餐", "fork.knife"), ("午餐", "fork.knife"), ("晚餐", "fork.knife"), ("外卖", "takeoutbag.and.cup.and.straw")]),
        .init(name: "交通", icon: "bus", colorHex: "4A90D9",
              children: [("公交地铁", "bus"), ("打车", "car"), ("加油", "fuelpump")]),
        .init(name: "购物", icon: "bag", colorHex: "F06292"),
        .init(name: "居住", icon: "house", colorHex: "8E7CF8"),
        .init(name: "娱乐", icon: "gamecontroller", colorHex: "26C6DA"),
        .init(name: "医疗", icon: "cross.case", colorHex: "4CAF50"),
        .init(name: "教育", icon: "book", colorHex: "5C6BC0"),
        .init(name: "通讯", icon: "phone", colorHex: "29B6F6"),
        .init(name: "人情", icon: "gift", colorHex: "EF5350"),
        .init(name: "宠物", icon: "pawprint", colorHex: "8D6E63"),
        .init(name: "旅行", icon: "airplane", colorHex: "26A69A"),
        .init(name: "其他", icon: "ellipsis", colorHex: "9E9E9E"),
    ]

    static let incomeCategories: [SeedCategory] = [
        .init(name: "工资", icon: "banknote", colorHex: "66BB6A"),
        .init(name: "奖金", icon: "rosette", colorHex: "FFA726"),
        .init(name: "理财", icon: "chart.line.uptrend.xyaxis", colorHex: "42A5F5"),
        .init(name: "红包", icon: "gift", colorHex: "EC407A"),
        .init(name: "兼职", icon: "briefcase", colorHex: "8D6E63"),
        .init(name: "报销", icon: "doc.text", colorHex: "26C6DA"),
        .init(name: "其他", icon: "ellipsis", colorHex: "9E9E9E"),
    ]

    static func ensureSeeded(context: ModelContext, defaults: UserDefaults = .standard) {
        // 已存在系统分类则跳过分类种子（iCloud 同步先到的场景）
        let existingCategories = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        if !existingCategories.contains(where: { $0.isSystem }) {
            seedCategories(context: context)
        }

        let existingAccounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        if existingAccounts.isEmpty {
            seedAccounts(context: context)
        }

        defaults.set(true, forKey: seedFlagKey)
        try? context.save()
    }

    private static func seedCategories(context: ModelContext) {
        for (index, seed) in expenseCategories.enumerated() {
            let parent = Category(name: seed.name, kind: .expense, icon: seed.icon,
                                  colorHex: seed.colorHex, sortOrder: index, isSystem: true)
            context.insert(parent)
            for (childIndex, child) in seed.children.enumerated() {
                context.insert(Category(name: child.0, kind: .expense, icon: child.1,
                                        colorHex: seed.colorHex, sortOrder: childIndex,
                                        isSystem: true, parent: parent))
            }
        }
        for (index, seed) in incomeCategories.enumerated() {
            context.insert(Category(name: seed.name, kind: .income, icon: seed.icon,
                                    colorHex: seed.colorHex, sortOrder: index, isSystem: true))
        }
    }

    private static func seedAccounts(context: ModelContext) {
        let seeds: [(String, AccountKind, String, Int)] = [
            ("现金", .cash, "FFB300", 0),
            ("储蓄卡", .bank, "4A90D9", 1),
            ("支付宝", .alipay, "1677FF", 2),
            ("微信", .wechat, "07C160", 3),
            ("信用卡", .credit, "EF5350", 4),
        ]
        for (name, kind, hex, order) in seeds {
            context.insert(Account(name: name, kind: kind, colorHex: hex, sortOrder: order))
        }
    }
}
