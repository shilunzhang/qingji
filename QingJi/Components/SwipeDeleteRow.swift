import SwiftUI

/// 非 List 容器（卡片 / ScrollView）中的左滑删除行（v1.4.2，F-02/F-04）。
///
/// List 里用系统 .swipeActions 即可；VStack 卡片内的行用它实现同等交互：
/// - 横向拖拽露出红色删除按钮，松手按阈值吸附（露出 / 回弹）
/// - 一次滑过 fullSwipe 阈值直接删除
/// - 仅响应横向为主的拖拽，纵向滚动不受影响；点击（编辑）不受影响
struct SwipeDeleteRow<Content: View>: View {
    var onDelete: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var offsetX: CGFloat = 0
    @State private var settledX: CGFloat = 0

    /// 露出删除按钮的吸附宽度
    private let revealWidth: CGFloat = 76
    /// 超过此负向偏移直接删除（约 1.8 倍露出宽度）
    private let fullSwipeWidth: CGFloat = 140

    var body: some View {
        ZStack(alignment: .trailing) {
            deleteButton
                .opacity(offsetX < -revealWidth / 3 ? 1 : 0)
            content()
                .offset(x: offsetX)
                .gesture(dragGesture)
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            onDelete()
        } label: {
            Image(systemName: "trash.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: revealWidth - 10, height: 40)
                .background(Theme.alert, in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("删除")
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 15)
            .onChanged { value in
                // 横向为主的拖拽才处理，纵向交给外层滚动
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let proposed = settledX + value.translation.width
                offsetX = min(0, max(-fullSwipeWidth - 30, proposed))
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    offsetX = settledX
                    return
                }
                let proposed = settledX + value.translation.width
                withAnimation(.spring(duration: 0.25)) {
                    if proposed < -fullSwipeWidth {
                        // 整行滑过阈值：直接删除
                        offsetX = 0
                        settledX = 0
                        onDelete()
                    } else if proposed < -revealWidth / 2 {
                        settledX = -revealWidth
                        offsetX = -revealWidth
                    } else {
                        settledX = 0
                        offsetX = 0
                    }
                }
            }
    }
}
