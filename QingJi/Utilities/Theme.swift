import SwiftUI

/// 主题与颜色工具（文档 §6）
enum Theme {
    /// 收入绿 / 转账蓝；支出用主文本色（文档 6.3）
    static let income = Color(red: 0.20, green: 0.78, blue: 0.35)
    static let transfer = Color(red: 0.00, green: 0.48, blue: 1.00)
    static let alert = Color.red

    /// 分类默认色板
    static let palette: [String] = [
        "FF8A3D", "F06292", "4A90D9", "8E7CF8", "26C6DA",
        "4CAF50", "FFB300", "EF5350", "8D6E63", "78909C",
    ]
}

extension Color {
    /// "RRGGBB" 或 "#RRGGBB"
    init(hex: String) {
        var value: UInt64 = 0
        var hexString = hex
        if hexString.hasPrefix("#") { hexString.removeFirst() }
        Scanner(string: hexString).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    /// 从 hex 字符串取更亮的展示色（用于图标底色）
    static func categoryBackground(_ hex: String) -> Color {
        Color(hex: hex).opacity(0.18)
    }
}

/// 卡片容器样式
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}

/// 水滴玻璃卡片：iOS 26 用 Liquid Glass 效果，低版本回退材质模糊
extension View {
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                )
        }
    }
}
