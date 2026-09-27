import SwiftUI

/// 疑似重复/阻止弹窗组（文档 F-14）——供各入账入口复用
struct DuplicateAlerts: ViewModifier {
    @Binding var pendingDuplicate: DuplicateMatch?
    @Binding var confirmEntryID: UUID?
    @Binding var blockMessage: String?
    var onConfirm: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("疑似重复账目", isPresented: Binding(
                get: { pendingDuplicate != nil },
                set: { if !$0 { pendingDuplicate = nil } }
            )) {
                Button("仍要保存") { onConfirm() }
                Button("取消", role: .cancel) {}
            } message: {
                Text(pendingDuplicate.map { "已有一笔 \($0.summary)，确认仍要保存这笔吗？" } ?? "")
            }
            .alert("无法保存", isPresented: Binding(
                get: { blockMessage != nil },
                set: { if !$0 { blockMessage = nil } }
            )) {
                Button("好的", role: .cancel) {}
            } message: {
                Text(blockMessage ?? "")
            }
    }
}
