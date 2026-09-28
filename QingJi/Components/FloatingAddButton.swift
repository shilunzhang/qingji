import SwiftUI

/// 右下角浮动记账按钮（文档 v1.4）：
/// 固定锚点在右下角（收起/展开均不移动），
/// 点按展开 4 个弧形环绕入口，点菜单外任意位置或再点 + 收起。
///
/// v1.4.1 交互加固：
/// - frame 必须显式 alignment: .bottomTrailing——默认 .center 会让收起态
///   菜单簇居中到屏幕中间，展开时又跳回右下角（视觉与命中区错位的根源）
/// - 所有按钮显式 contentShape(Circle())，命中区外扩，杜绝小目标点不中
/// - 液态玻璃作为图标下方的背景层渲染，不包裹按钮手势内容，
///   避免 glassEffect(.interactive()) 吞点击（真机实测症状：展开后按钮全部无响应）
struct FloatingAddButton: View {
    var onSelect: (AddSheet) -> Void

    @State private var isExpanded = false

    // v1.4.8：批量扫描移至明细页下拉触发，剩 3 个入口；
    // 弧线不占 180° 平左位，150°/120°/90° 均匀 30° 分布（左上 → 正上）
    private let radius: CGFloat = 116
    private let mainSize: CGFloat = 58
    private let arcSize: CGFloat = 48
    private let edgeTrailing: CGFloat = 18
    private let edgeBottom: CGFloat = 90

    private var arcItems: [(icon: String, hex: String, angle: Double, sheet: AddSheet)] {
        [
            ("photo.on.rectangle", "4A90D9", 150, .screenshotImport),
            ("camera", "FF8A3D", 120, .cameraCapture),
            ("pencil.line", "4CAF50", 90, .manualAdd(kind: .expense, prefill: nil)),
        ]
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if isExpanded {
                collapseCatcher
            }
            menuCluster
                .padding(.trailing, edgeTrailing)
                .padding(.bottom, edgeBottom)
        }
        // 关键：显式右下对齐。收起态 ZStack 只有菜单簇大小，
        // 没有 alignment 会以默认 .center 居中到屏幕中间导致按钮瞬移
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .animation(.spring(duration: 0.32), value: isExpanded)
    }

    /// 展开时铺满全屏的透明层：点击菜单外任意位置收起
    private var collapseCatcher: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { isExpanded = false }
            .ignoresSafeArea()
            .transition(.opacity)
            .accessibilityLabel("收起菜单")
    }

    /// 弧形子按钮 + 主按钮（始终位于最上层）
    private var menuCluster: some View {
        ZStack {
            if isExpanded {
                ForEach(arcItems.indices, id: \.self) { index in
                    arcButton(arcItems[index])
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            mainButton
        }
        .zIndex(1)
    }

    // MARK: - 主按钮（液态玻璃）

    private var mainButton: some View {
        Button {
            isExpanded.toggle()
        } label: {
            ZStack {
                glassCircle(size: mainSize)
                Image(systemName: isExpanded ? "xmark" : "plus")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: mainSize, height: mainSize)
            .contentShape(Circle().inset(by: -8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "收起记账菜单" : "展开记账菜单")
    }

    // MARK: - 弧形子按钮

    private func arcButton(_ item: (icon: String, hex: String, angle: Double, sheet: AddSheet)) -> some View {
        let radians = item.angle * Double.pi / 180
        return Button {
            isExpanded = false
            onSelect(item.sheet)
        } label: {
            ZStack {
                glassCircle(size: arcSize)
                Image(systemName: item.icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color(hex: item.hex))
            }
            .frame(width: arcSize, height: arcSize)
            .contentShape(Circle().inset(by: -12)) // 命中区外扩 12pt，小目标也易点中
        }
        .buttonStyle(.plain)
        .offset(x: cos(radians) * radius, y: -sin(radians) * radius)
        .accessibilityLabel(item.sheet.title)
    }

    /// 液态玻璃背景层：iOS 26 用 glassEffect，低版本用超薄材质。
    /// 作为图标下方的兄弟层渲染，不包裹手势内容
    @ViewBuilder
    private func glassCircle(size: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            Circle()
                .fill(Color.clear)
                .frame(width: size, height: size)
                .glassEffect(.regular, in: Circle())
        } else {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: size, height: size)
                .overlay(
                    Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.15), radius: 5, y: 2)
        }
    }
}

extension AddSheet {
    /// 无障碍标签（与弧形入口一一对应）
    var title: String {
        switch self {
        case .screenshotImport: return "截图入账"
        case .albumScan: return "扫描相册新截图"
        case .cameraCapture: return "拍照入账"
        case .manualAdd: return "手动记账"
        }
    }
}
