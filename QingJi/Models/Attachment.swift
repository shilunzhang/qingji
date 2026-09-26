import Foundation
import SwiftData

/// 凭证图（文档 F-05）。级联挂在 Transaction 上。
@Model
final class Attachment {
    var id: UUID = UUID()
    /// JPEG 数据；写入前压缩至长边 ≤1200px（文档 §8 风险表）
    @Attribute(.externalStorage) var data: Data = Data()
    var mimeType: String = "image/jpeg"
    var createdAt: Date = .now

    @Relationship var transaction: Transaction? = nil

    init(data: Data, mimeType: String = "image/jpeg") {
        self.data = data
        self.mimeType = mimeType
    }
}
