import SwiftUI

/// 隐私模糊（v1.4.6，F-20）：
/// 全局开关持久化于 UserDefaults，@AppStorage 在明细页/我的页等多处声明会自动同步刷新。
/// 默认开启 = 模糊金额数字保护隐私；点眼睛图标切换。
enum PrivacyBlur {
    static let storageKey = "qingji.privacy.blurOn"
}

/// 数字/内容隐私模糊修饰：开关开启时施加高斯模糊（短动画过渡）
private struct PrivacyMaskModifier: ViewModifier {
    @AppStorage(PrivacyBlur.storageKey) private var blurOn = true

    func body(content: Content) -> some View {
        content
            .blur(radius: blurOn ? 5 : 0)
            .animation(.easeInOut(duration: 0.15), value: blurOn)
    }
}

extension View {
    /// 隐私开关开启时模糊此内容（只用于金额区域，勿包住开关本身）
    func privacyMask() -> some View {
        modifier(PrivacyMaskModifier())
    }
}

/// 眼睛开关按钮（明细页汇总卡 / 我的页净资产共用，状态全局同步）
struct PrivacyEyeButton: View {
    @AppStorage(PrivacyBlur.storageKey) private var blurOn = true

    var body: some View {
        Button {
            blurOn.toggle()
        } label: {
            Image(systemName: blurOn ? "eye.slash" : "eye")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(blurOn ? "显示金额" : "隐藏金额")
    }
}
