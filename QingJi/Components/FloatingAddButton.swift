import SwiftUI

/// 右下角浮动记账按钮（文档 v1.4）：
/// 固定位置，点按展开 4 个弧形环绕的入口图标
struct FloatingAddButton: View {
    var onSelect: (AddSheet) -> Void

    @State private var isExpanded = false

    // 问题4：半径加大，角度均匀分布（30° 间隔）
    private let radius: CGFloat = 116

    private var arcItems: [(icon: String, hex: String, angle: Double, sheet: AddSheet)] {
        [
            ("photo.on.rectangle", "4A90D9", 180, .screenshotImport),
            ("doc.text.magnifyingglass", "8E7CF8", 150, .albumScan),
            ("camera", "FF8A3D", 120, .cameraCapture),
            ("pencil.line", "4CAF50", 90, .manualAdd(kind: .expense, prefill: nil)),
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
        .animation(.spring(duration: 0.32), value: isExpanded)
    }

    // 问题1：主按钮使用液态玻璃
    @ViewBuilder
    private var mainButton: some View {
        Button {
            withAnimation(.spring(duration: 0.32)) { isExpanded.toggle() }
        } label: {
            if #available(iOS 26.0, *) {
                Image(systemName: isExpanded ? "xmark" : "plus")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 58, height: 58)
                    .glassEffect(.regular.interactive(), in: Circle())
            } else {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 58, height: 58)
                        .overlay(
                            Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                        )
                    Image(systemName: isExpanded ? "xmark" : "plus")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                }
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
            }
        }
        .buttonStyle(.plain)
    }

    // 问题4：弧形子项也用液态玻璃
    private func arcButton(_ item: (icon: String, hex: String, angle: Double, sheet: AddSheet)) -> some View {
        let radians = item.angle * Double.pi / 180
        return Button {
            withAnimation(.spring(duration: 0.3)) { isExpanded = false }
            onSelect(item.sheet)
        } label: {
            if #available(iOS 26.0, *) {
                Image(systemName: item.icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color(hex: item.hex))
                    .frame(width: 48, height: 48)
                    .glassEffect(.regular.interactive(), in: Circle())
            } else {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 48, height: 48)
                        .overlay(
                            Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                        )
                    Image(systemName: item.icon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color(hex: item.hex))
                }
                .shadow(color: .black.opacity(0.15), radius: 5, y: 2)
            }
        }
        .buttonStyle(.plain)
        .offset(x: cos(radians) * radius, y: -sin(radians) * radius)
    }
}
