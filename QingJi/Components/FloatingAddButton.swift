import SwiftUI

/// 右下角浮动记账按钮（文档 v1.4）：
/// 固定位置，点按展开 4 个弧形环绕的彩色入口图标
struct FloatingAddButton: View {
    var onSelect: (AddSheet) -> Void

    @State private var isExpanded = false

    private let radius: CGFloat = 92

    private var arcItems: [(icon: String, hex: String, angle: Double, sheet: AddSheet)] {
        [
            ("photo.on.rectangle", "4A90D9", 180, .screenshotImport),
            ("doc.text.magnifyingglass", "8E7CF8", 145, .albumScan),
            ("camera", "FF8A3D", 110, .cameraCapture),
            ("pencil.line", "4CAF50", 80, .manualAdd(kind: .expense, prefill: nil)),
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

    private var mainButton: some View {
        Button {
            withAnimation(.spring(duration: 0.32)) { isExpanded.toggle() }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 56, height: 56)
                Image(systemName: isExpanded ? "xmark" : "plus")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
            }
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }

    private func arcButton(_ item: (icon: String, hex: String, angle: Double, sheet: AddSheet)) -> some View {
        let radians = item.angle * Double.pi / 180
        return Button {
            withAnimation(.spring(duration: 0.3)) { isExpanded = false }
            onSelect(item.sheet)
        } label: {
            ZStack {
                Circle()
                    .fill(Color(hex: item.hex))
                    .frame(width: 46, height: 46)
                Image(systemName: item.icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .offset(x: cos(radians) * radius, y: -sin(radians) * radius)
    }
}
