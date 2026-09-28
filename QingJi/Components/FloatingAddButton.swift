import SwiftUI

/// 右下角浮动记账按钮（文档 v1.4 / v1.5.0）：
/// - 点按展开 3 个弧形入口；点外部或再点 + 收起
/// - v1.5.0 长按 0.3s 可拖动：拖动中自由跟随手指，松手水平磁吸回屏幕右缘，
///   纵向停留在松手高度（归一化持久化，重启保留）
/// - 弧形方向随高度自适应（y 为从屏幕底部量的归一化高度）：
///   下部 y<0.3 → 左上扇 150°/120°/90°（默认）
///   中部 0.3~0.7 → 左侧竖扇 210°/180°/150°（围绕正左均匀分布）
///   上部 y>0.7 → 左下扇 210°/240°/270°（与下部镜像对称，均不紧贴屏幕边缘）
struct FloatingAddButton: View {
    var onSelect: (AddSheet) -> Void

    @State private var isExpanded = false

    /// FAB 中心纵向位置（屏幕高度归一化，从底部量），跨启动持久化
    @AppStorage("qingji.fab.yNormFromBottom") private var yNormFromBottom: Double = 0.14
    /// 拖动中的实时位移（手势结束自动归零）
    @GestureState private var dragTranslation: CGSize = .zero

    private let radius: CGFloat = 116
    private let mainSize: CGFloat = 58
    private let arcSize: CGFloat = 48
    private let snapTrailing: CGFloat = 18
    /// 顶部安全线（状态栏 + 余量）
    private let dragMinY: CGFloat = 120
    /// 底部安全线（Tab 栏之上 + 余量）
    private let dragBottomMargin: CGFloat = 100

    // MARK: - 弧形区域

    private enum ArcRegion { case bottom, middle, top }

    private var arcRegion: ArcRegion {
        if yNormFromBottom > 0.7 { return .top }
        if yNormFromBottom >= 0.3 { return .middle }
        return .bottom
    }

    private var arcAngles: [Double] {
        switch arcRegion {
        case .bottom: return [150, 120, 90]   // 左上扇（默认）
        case .middle: return [210, 180, 150]  // 左侧竖扇，围绕正左均匀 30°
        case .top: return [210, 240, 270]     // 左下扇，与底部镜像对称
        }
    }

    private var arcItems: [(icon: String, hex: String, angle: Double, sheet: AddSheet)] {
        let entries: [(icon: String, hex: String, sheet: AddSheet)] = [
            ("photo.on.rectangle", "4A90D9", .screenshotImport),
            ("camera", "FF8A3D", .cameraCapture),
            ("pencil.line", "4CAF50", .manualAdd(kind: .expense, prefill: nil)),
        ]
        return (0..<entries.count).map { i in
            (icon: entries[i].icon, hex: entries[i].hex, angle: arcAngles[i], sheet: entries[i].sheet)
        }
    }

    // MARK: - 布局

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 展开时铺一层全屏透明捕获层，点击菜单外任意位置即收起
                if isExpanded {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { isExpanded = false }
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .accessibilityLabel("收起菜单")
                }
                ZStack {
                    if isExpanded {
                        ForEach(arcItems.indices, id: \.self) { index in
                            arcButton(arcItems[index])
                                .transition(.scale(scale: 0.4).combined(with: .opacity))
                        }
                    }
                    mainButton(fabDragGesture(in: geo))
                }
                .zIndex(1)
                .position(center(in: geo, translation: dragTranslation))
            }
        }
        .animation(.spring(duration: 0.32), value: isExpanded)
        .animation(.spring(duration: 0.35), value: yNormFromBottom) // 松手磁吸/弧向切换平滑过渡
    }

    /// FAB 静止中心；拖动中叠加位移（x 允许左移跟随、右不越右缘；y 限制在安全区内）
    private func center(in geo: GeometryProxy, translation: CGSize) -> CGPoint {
        let h = geo.size.height
        let restY = min(max((1 - yNormFromBottom) * h, dragMinY), h - dragBottomMargin)
        let restX = geo.size.width - snapTrailing - mainSize / 2
        let x = min(max(restX + translation.width, snapTrailing + mainSize / 2), restX)
        let y = min(max(restY + translation.height, dragMinY), h - dragBottomMargin)
        return CGPoint(x: x, y: y)
    }

    // MARK: - 手势（长按 0.3s 拖动）

    private func fabDragGesture(in geo: GeometryProxy) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 1))
            .updating($dragTranslation) { value, state, _ in
                switch value {
                case .first(true):
                    state = .zero
                case .second(true, let drag?):
                    state = drag.translation
                    if isExpanded { isExpanded = false } // 拖动时收起菜单
                default:
                    state = .zero
                }
            }
            .onEnded { value in
                guard case .second(true, let drag?) = value else { return }
                let h = geo.size.height
                let restY = min(max((1 - yNormFromBottom) * h, dragMinY), h - dragBottomMargin)
                let newY = min(max(restY + drag.translation.height, dragMinY), h - dragBottomMargin)
                // 只保留纵向结果；水平回落右缘（x 由 restX 决定）
                withAnimation(.spring(duration: 0.35)) {
                    yNormFromBottom = 1 - Double(newY / h)
                }
            }
    }

    // MARK: - 主按钮

    private func mainButton(_ dragGesture: some Gesture) -> some View {
        ZStack {
            glassCircle(size: mainSize)
            Image(systemName: isExpanded ? "xmark" : "plus")
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.accentColor)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: mainSize, height: mainSize)
        .contentShape(Circle().inset(by: -8))
        .onTapGesture { isExpanded.toggle() } // 快速点按：展开/收起（长按不会触发）
        .gesture(dragGesture)                 // 长按 0.3s + 移动：拖动定位
        .accessibilityLabel(isExpanded ? "收起记账菜单" : "记账菜单，长按可拖动")
        .accessibilityAddTraits(.isButton)
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
            .contentShape(Circle().inset(by: -12)) // 命中区外扩 12pt
        }
        .buttonStyle(.plain)
        .offset(x: cos(radians) * radius, y: -sin(radians) * radius)
        .accessibilityLabel(item.sheet.title)
    }

    /// 液态玻璃背景层：iOS 26 用 glassEffect，低版本用超薄材质
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
