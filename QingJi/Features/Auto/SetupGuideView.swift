import SwiftUI
import UserNotifications

/// 快捷指令自动化配置指引（文档 F-12 交付物）：一次性配置，2 分钟
struct SetupGuideView: View {

    var body: some View {
        List {
            Section {
                Button {
                    Task { _ = await CaptureNotificationHandler.requestAuthorizationIfNeeded() }
                } label: {
                    Label("允许轻记发送通知", systemImage: "bell.badge")
                }
            } header: {
                Text("前置条件")
            } footer: {
                Text("确认卡通过系统通知弹出，请先允许通知权限（已允许则无需操作）")
            }

            Section("创建自动化（一次性配置）") {
                guideRow(1, "打开系统「快捷指令」App → 底部「自动化」→「新建自动化」")
                guideRow(2, "选择「App」→ 事件选「关闭时」→ 勾选「支付宝」「微信」→ 下一步")
                guideRow(3, "添加动作：搜索「拍摄屏幕快照」并添加")
                guideRow(4, "再添加动作：搜索「轻记」→ 选择「截图入账」→「截图」参数自动取上一步的屏幕快照")
                guideRow(5, "最后添加动作：「删除照片」→ 选择「屏幕快照」变量（快照不留存）")
                guideRow(6, "关闭「运行前询问」，保存完成")
            }

            Section {
                guideRow(7, "付款后从支付宝/微信切走 → 自动弹出通知 → 点「入账」")
                guideRow(8, "想零操作？在「我的 → 自动记账」打开「静默自动入账」")
            } header: {
                Text("之后的体验")
            } footer: {
                Text("提示：支付成功页停留越稳识别越准；识别不到时静默忽略，可用「截图记账」「账单导入」兜底。同一支付页与 10 分钟内同额账目都会被自动防重")
            }
        }
        .navigationTitle("快捷指令自动化")
    }

    private func guideRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.15))
                .foregroundStyle(Color.accentColor)
                .clipShape(Circle())
            Text(text)
                .font(.subheadline)
        }
        .padding(.vertical, 2)
    }
}
