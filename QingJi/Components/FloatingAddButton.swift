import SwiftUI

/// 右下角浮动记账按钮（文档 v1.4）：
/// - 可拖动调整位置（位置持久化）
/// - 点按展开 4 个弧形环绕的入口图标
struct FloatingAddButton: View {
    var onSelect: (AddSheet) -> Void

    /// 相对默认锚点（右下角）的持久化偏移
    @AppStorage("qingji.fab.dx") private var dx: Double = 0
    @AppStorage("qingji.fab.dy") private var dy: Double = 0

    @State private var isExpanded = false
    @State private var dragTranslation: CGSize = .zero

    /// 弧形半径与各入口角度（度）：从左侧扫到上方
    private let radius: CGFloat = 92
    private var arcItems: [(icon: String, hex: String, angle: Double, sheet: AddSheet)] {
        [
            ("photo.on.rectangle", "4A90D9", 180, .screenshotImport),
            ("doc.text.magnifyingglass", "8E7CF8", 142, .albumScan),
            ("camera", "FF8A3D", 104, .cameraCapture),
            ("pencil.line", "4CAF50", 68, .manualAdd(kind: .expense, prefill: nil)),
        ]
    }

    var body: some View {
        ZStack {
            if isExpanded {
                ForEach(arcItems.indices, id: \.self) { index in
                    arcButton(arcItems[index])
                }
            }
            mainButton
        }
        .offset(x: dx + dragTranslation.width, y: dy + dragTranslation.height)
        .animation(.spring(duration: 0.32), value: isExpanded)
    }

    // MARK: - 主按钮（点按展开/收起，拖动调位置）

    private var mainButton: some View {
        content
            .onTapGesture {
                withAnimation(.spring(duration: 0.32)) { isExpanded.toggle() }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        dragTranslation = value.translation
                    }
                    .onEnded { value in
                        dx += value.translation.width
                        dy += value.translation.height
                        dragTranslation = .zero
                    }
            )
    }

    @ViewBuilder
    private var content: some View {
        if #available(iOS 26.0, *) {
            Image(systemName: isExpanded ? "xmark" : "plus")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .glassEffect(.regular.tint(.accent).interactive(), in: Circle())
                .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        } else {
            Image(systemName: isExpanded ? "xmark" : "plus")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Circle().fill(Color.accentColor))
                .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
        }
    }

    // MARK: - 弧形子项

    @ViewBuilder
    private func arcButton(_ item: (icon: String, hex: String, angle: Double, sheet: AddSheet)) -> some View {
        let radians = item.angle * Double.pi / 180
        Button {
            withAnimation(.spring(duration: 0.3)) { isExpanded = false }
            onSelect(item.sheet)
        } label: {
            Image(systemName: item.icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Circle().fill(Color(hex: item.hex)))
                .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .offset(x: cos(radians) * radius, y: -sin(radians) * radius)
    }
}
