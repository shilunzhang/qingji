import SwiftUI

/// 浮动记账按钮（文档 v1.4 / v1.5.3）：
/// - 点按展开 3 个弧形入口；点外部或再点 + 收起
/// - 小白点手感拖动：零延迟跟手、可拖至任意处、松手贴最近左右边缘、纵向高度持久化
/// - v1.5.3 拖动重构（真机反馈"不跟手/颤动"三根源）：
///   ① 手势改挂在**固定命中层**上（不随拖动位移），视觉层单独跟随——
///      手势挂在移动视图上会被 iOS 26 重新命中测试打断重启（位移归零→累计→颤动）
///   ② 拖动中液态玻璃降级为超薄材质（glassEffect 随位置每帧重采样背景，开销大）
///   ③ 拖动状态隔离进 FabDragLayer 子视图（父视图 GeometryReader/ForEach 不再每帧重算）
/// - 弧形 90° 象限内 45° 均匀排开；左贴靠时水平镜像朝屏幕内侧
struct FloatingAddButton: View {
    var onSelect: (AddSheet) -> Void

    @State private var isExpanded = false
    /// v1.5.3 拖动中（用于玻璃降级，见 ②）
    @State private var isDraggingNow = false

    /// FAB 中心纵向位置（屏幕高度归一化，从底部量），跨启动持久化
    @AppStorage("qingji.fab.yNormFromBottom") private var yNormFromBottom: Double = 0.14
    /// 贴靠侧：true=右缘，false=左缘
    @AppStorage("qingji.fab.sideRight") private var sideRight = true

    private let radius: CGFloat = 116
    private let mainSize: CGFloat = 58
    private let arcSize: CGFloat = 48
    private let snapInset: CGFloat = 18
    private let topSafe: CGFloat = 90
    /// 底部安全线：FAB 中心距底 ≥160pt（弧形横向臂不压 Tab 栏）
    private let bottomSafe: CGFloat = 160

    // MARK: - 弧形区域（90° 象限内 45° 均匀排开）

    private enum ArcRegion { case bottom, middle, top }

    private var arcRegion: ArcRegion {
        if yNormFromBottom > 0.7 { return .top }
        if yNormFromBottom >= 0.3 { return .middle }
        return .bottom
    }

    /// 右贴靠的基础角度；左贴靠时以竖直轴镜像（θ → 180°-θ），朝屏幕内侧展开。
    /// v1.5.4 端点内收 7.5°（跨度 75°、间隔 37.5° 均匀）：端点落在象限边界时
    /// 90° 图标贴 + 号正上方（距屏幕边缘仅 47pt 一列）、180° 图标骑边平行线——均不美观
    private var arcAngles: [Double] {
        let base: [Double]
        switch arcRegion {
        case .bottom: base = [172.5, 135, 97.5]   // 截图、拍照、手动：左 → 上
        case .middle: base = [217.5, 180, 142.5]  // 左下 → 左上，围绕正左
        case .top: base = [187.5, 225, 262.5]     // 左 → 下，与底部镜像对称
        }
        guard !sideRight else { return base }
        return base.map { ((180 - $0) + 360).truncatingRemainder(dividingBy: 360) }
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
                FabDragLayer(
                    rest: restCenter(in: geo),
                    bounds: geo.size,
                    expanded: isExpanded,
                    onTap: { isExpanded.toggle() },
                    onDragStart: {
                        if isExpanded { isExpanded = false }
                        isDraggingNow = true
                    },
                    onDock: { goRight, yNorm in
                        isDraggingNow = false
                        sideRight = goRight
                        yNormFromBottom = yNorm
                    }
                ) {
                    menuCluster
                }
            }
        }
        .animation(.spring(duration: 0.32), value: isExpanded)
        .animation(.spring(duration: 0.35), value: yNormFromBottom)
        .animation(.easeInOut(duration: 0.15), value: isDraggingNow)
    }

    /// 静止停靠中心：x 贴当前侧边缘，y 按持久化归一化高度（含安全区钳制）
    private func restCenter(in geo: GeometryProxy) -> CGPoint {
        let h = geo.size.height
        let y = min(max((1 - yNormFromBottom) * h, topSafe), h - bottomSafe)
        let x = sideRight ? geo.size.width - snapInset - mainSize / 2
                          : snapInset + mainSize / 2
        return CGPoint(x: x, y: y)
    }

    /// 视觉簇：弧形子按钮 + 主按钮（无手势——手势在 FabDragLayer 的固定命中层上）
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

    private var mainButton: some View {
        ZStack {
            glassCircle(size: mainSize)
            Image(systemName: isExpanded ? "xmark" : "plus")
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.accentColor)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: mainSize, height: mainSize)
        .allowsHitTesting(false) // 命中全走固定命中层
        .accessibilityHidden(true)
    }

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
        .buttonStyle(PressScaleButtonStyle())
        .offset(x: cos(radians) * radius, y: -sin(radians) * radius)
        .accessibilityLabel(item.sheet.title)
    }

    /// v1.5.2 弧形子按钮按压反馈：按下轻微缩小，松手弹回
    /// （注：Xcode 26 SDK 中 Animation.spring 成为静态属性，遮蔽带 extraBounce 的
    /// 函数重载导致编译错误，统一改用 spring(duration:)）
    private struct PressScaleButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.88 : 1)
                .animation(.spring(duration: 0.2), value: configuration.isPressed)
        }
    }

    /// 液态玻璃背景层：拖动中降级超薄材质（避免逐帧背景重采样），低版本系统用超薄材质
    @ViewBuilder
    private func glassCircle(size: CGFloat) -> some View {
        if #available(iOS 26.0, *), !isDraggingNow {
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

// MARK: - 拖动层（v1.5.3：固定命中层 + 视觉层分离）

/// 手势挂在**固定命中层**（不随拖动位移的透明圆）上：
/// 挂在移动视图上会被 iOS 26 重新命中测试打断重启 → 位移归零再累计 → 颤动/不跟手。
/// 视觉层（content）通过 offset 跟随；拖动状态隔离在本视图，父视图不逐帧重算。
private struct FabDragLayer<Content: View>: View {
    let rest: CGPoint
    let bounds: CGSize
    var expanded: Bool
    var onTap: () -> Void
    var onDragStart: () -> Void
    var onDock: (_ goRight: Bool, _ yNormFromBottom: Double) -> Void
    @ViewBuilder var content: () -> Content

    @State private var dragOffset: CGSize = .zero
    @GestureState private var isTouching = false
    /// 已越过点按阈值（真拖动开始），用于 onDragStart 只触发一次
    @State private var didStartDrag = false

    private let mainSize: CGFloat = 58
    private let edgeInset: CGFloat = 47          // snapInset 18 + 半径 29
    private let topSafe: CGFloat = 90
    private let bottomSafe: CGFloat = 160
    private let tapThreshold: CGFloat = 12

    var body: some View {
        // 视觉层（下层）：跟随手指位移（钳制的是"结果坐标"，不是偏移量本身）；
        // 弧形按钮可点击（主按钮区域被上层命中区覆盖）
        content()
            .scaleEffect(isTouching && !expanded ? 1.2 : 1)
            .animation(.spring(duration: 0.25), value: isTouching)
            .position(x: (rest.x + dragOffset.width).clamped(to: liveXRange),
                      y: (rest.y + dragOffset.height).clamped(to: liveYRange))
        // 固定命中层（上层）：位置恒为停靠点，手势全程不被打断
        Circle()
            .fill(Color.clear)
            .frame(width: mainSize, height: mainSize)
            .contentShape(Circle().inset(by: -10))
            .position(rest)
            .gesture(fabGesture)
            .accessibilityLabel("记账菜单，可拖动")
            .accessibilityAddTraits(.isButton)
    }

    private var liveXRange: ClosedRange<CGFloat> {
        edgeInset...max(edgeInset, bounds.width - edgeInset)
    }

    private var liveYRange: ClosedRange<CGFloat> {
        topSafe...max(topSafe, bounds.height - bottomSafe)
    }

    private var fabGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isTouching) { _, state, _ in
                state = true // 触摸期间保持放大（含拖动全程），松手自动复位
            }
            .onChanged { value in
                dragOffset = value.translation
                if !didStartDrag,
                   hypot(value.translation.width, value.translation.height) >= tapThreshold {
                    didStartDrag = true
                    onDragStart()
                }
            }
            .onEnded { value in
                let distance = hypot(value.translation.width, value.translation.height)
                defer { didStartDrag = false }
                guard distance >= tapThreshold else {
                    dragOffset = .zero
                    onTap() // 小位移 = 点按：展开/收起
                    return
                }
                let finalX = (rest.x + value.translation.width).clamped(to: liveXRange)
                let finalY = (rest.y + value.translation.height).clamped(to: liveYRange)
                let goRight = finalX >= bounds.width / 2
                // 拖动偏移清零与新停靠位同一次弹性动画结算：从松手点顺滑滑向最近边缘
                withAnimation(.spring(duration: 0.3)) {
                    dragOffset = .zero
                    onDock(goRight, 1 - Double(finalY / max(bounds.height, 1)))
                }
            }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
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
