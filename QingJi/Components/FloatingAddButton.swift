import SwiftUI

/// 浮动记账按钮（文档 v1.4 / v1.5.1）：
/// - 点按展开 3 个弧形入口；点外部或再点 + 收起
/// - v1.5.1 拖动重构（小白点手感）：DragGesture(minimumDistance: 0) 零延迟全程跟手，
///   可拖至屏幕任意处；松手位移 <12pt 判为点按，否则弹性贴回**最近的**左/右边缘，
///   纵向停留（归一化持久化，重启保留）。旧版 LongPress sequenced Drag 在 0.3s 内
///   移动即判定失败导致"拖不动"，已弃用。
/// - 弧形方向随位置自适应（y 为从屏幕底部量的归一化高度），三档均在 90° 象限内
///   以 45° 均匀排开（端点贴象限边界），左贴靠时水平镜像朝屏幕内侧：
///   下部 y<0.3 → 上方象限 180°/135°/90°（截图/拍照/手动，左→上）
///   中部 0.3~0.7 → 左侧象限 225°/180°/135°（围绕正左）
///   上部 y>0.7 → 下方象限 180°/225°/270°（与下部镜像对称）
struct FloatingAddButton: View {
    var onSelect: (AddSheet) -> Void

    @State private var isExpanded = false

    /// FAB 中心纵向位置（屏幕高度归一化，从底部量），跨启动持久化
    @AppStorage("qingji.fab.yNormFromBottom") private var yNormFromBottom: Double = 0.14
    /// v1.5.1 贴靠侧：true=右缘，false=左缘
    @AppStorage("qingji.fab.sideRight") private var sideRight = true
    /// 拖动中的实时位移（普通 @State：松手与停靠位在同一次动画里结算，避免回弹闪烁）
    @State private var dragOffset: CGSize = .zero

    private let radius: CGFloat = 116
    private let mainSize: CGFloat = 58
    private let arcSize: CGFloat = 48
    private let snapInset: CGFloat = 18
    private let topSafe: CGFloat = 90
    /// 底部安全线：FAB 中心距底 ≥160pt——否则弧形横向臂（180° 端点图标）会压在
    /// Tab 栏上沿（y≈733 vs 栏顶≈740），视觉上"贴屏幕"（真机反馈）
    private let bottomSafe: CGFloat = 160
    /// 松手位移小于此值视为点按（非拖动）
    private let tapThreshold: CGFloat = 12

    // MARK: - 弧形区域（90° 象限内 45° 均匀排开）

    private enum ArcRegion { case bottom, middle, top }

    private var arcRegion: ArcRegion {
        if yNormFromBottom > 0.7 { return .top }
        if yNormFromBottom >= 0.3 { return .middle }
        return .bottom
    }

    /// 右贴靠的基础角度；左贴靠时以竖直轴镜像（θ → 180°-θ），朝屏幕内侧展开
    private var arcAngles: [Double] {
        let base: [Double]
        switch arcRegion {
        case .bottom: base = [180, 135, 90]   // 截图、拍照、手动：左 → 上
        case .middle: base = [225, 180, 135]  // 左下 → 左上，围绕正左
        case .top: base = [180, 225, 270]     // 左 → 下，与底部镜像对称
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
                .position(liveCenter(in: geo))
            }
        }
        .animation(.spring(duration: 0.32), value: isExpanded)
        .animation(.spring(duration: 0.35), value: yNormFromBottom)
    }

    /// 静止停靠中心：x 贴当前侧边缘，y 按持久化的归一化高度（含安全区钳制）
    private func restCenter(in geo: GeometryProxy) -> CGPoint {
        let h = geo.size.height
        let y = min(max((1 - yNormFromBottom) * h, topSafe), h - bottomSafe)
        let x = sideRight ? geo.size.width - snapInset - mainSize / 2
                          : snapInset + mainSize / 2
        return CGPoint(x: x, y: y)
    }

    /// 拖动中的实时中心：停靠位 + 手指位移（钳制在安全区内，可到屏幕任意处）
    private func liveCenter(in geo: GeometryProxy) -> CGPoint {
        let rest = restCenter(in: geo)
        let x = min(max(rest.x + dragOffset.width, snapInset + mainSize / 2),
                    geo.size.width - snapInset - mainSize / 2)
        let y = min(max(rest.y + dragOffset.height, topSafe), geo.size.height - bottomSafe)
        return CGPoint(x: x, y: y)
    }

    // MARK: - 手势（小白点手感：零延迟跟手 + 贴边）

    private func fabDragGesture(in geo: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                dragOffset = value.translation
                // 超过点按阈值才算真拖动：收起菜单（纯点按不动菜单，交给 onEnded 切换）
                if hypot(value.translation.width, value.translation.height) >= tapThreshold,
                   isExpanded {
                    isExpanded = false
                }
            }
            .onEnded { value in
                let distance = hypot(value.translation.width, value.translation.height)
                guard distance >= tapThreshold else {
                    dragOffset = .zero
                    isExpanded.toggle() // 小位移 = 点按：展开/收起
                    return
                }
                let rest = restCenter(in: geo)
                let finalY = min(max(rest.y + value.translation.height, topSafe),
                                 geo.size.height - bottomSafe)
                let finalX = rest.x + value.translation.width
                let goRight = finalX >= geo.size.width / 2
                // 拖动偏移清零与新停靠位在同一次弹性动画里结算：
                // 视觉上从松手位置顺滑滑向最近边缘，无回跳
                withAnimation(.spring(duration: 0.3)) {
                    dragOffset = .zero
                    sideRight = goRight
                    yNormFromBottom = 1 - Double(finalY / geo.size.height)
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
        .gesture(dragGesture)
        .accessibilityLabel(isExpanded ? "收起记账菜单" : "记账菜单，可拖动")
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
