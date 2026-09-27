import SwiftUI

/// 右下角浮动记账按钮（文档 v1.4）：
/// 固定位置（右下角），点按展开 4 个弧形环绕的液态玻璃入口图标
struct FloatingAddButton: View {
    var onSelect: (AddSheet) -> Void

    @State private var isExpanded = false

    private let radius: CGFloat = 92

    private var arcItems: [(icon: String, hex: String, angle: Double, sheet: AddSheet)] {
        [
            ("photo.on.rectangle", "4A90D9", 180, .screenshotImport),
            ("doc.text.magnifyingglass", "8E7CF8", 140, .albumScan),
            ("camera", "FF8A3D", 100, .cameraCapture),
            ("pencil.line", "4CAF50", 60, .manualAdd(kind: .expense, prefill: nil)),
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

    // MARK: - 主按钮（纯 Button，确保点按 100% 可靠）

    private var mainButton: some View {
        Button {
            withAnimation(.spring(duration: 0.32)) { isExpanded.toggle() }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 56, height: 56)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                Image(systemName: isExpanded ? "xmark" : "plus")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 弧形子项（液态玻璃）

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
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .offset(x: cos(radians) * radius, y: -sin(radians) * radius)
        .transition(.scale(scale: 0.3).combined(with: .opacity))
    }
}
