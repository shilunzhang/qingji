import Foundation
import SwiftData

/// 标签（M1 仅数据模型，UI 编辑见文档 M2 计划）
@Model
final class Tag {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = "78909C"
    var createdAt: Date = Date.now

    @Relationship var transactions: [Transaction]? = nil

    init(name: String, colorHex: String = "78909C") {
        self.name = name
        self.colorHex = colorHex
    }
}
