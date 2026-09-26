import SwiftUI

/// 自定义数字键盘（文档 F-01）：0-9 + 小数点 + 退格，清空放在金额展示区
struct NumberPad: View {
    let onDigit: (String) -> Void
    let onDelete: () -> Void

    var body: some View {
        Grid(alignment: .center, horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                digit("7")
                digit("8")
                digit("9")
            }
            GridRow {
                digit("4")
                digit("5")
                digit("6")
            }
            GridRow {
                digit("1")
                digit("2")
                digit("3")
            }
            GridRow {
                digit(".")
                digit("0")
                deleteKey
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func digit(_ label: String) -> some View {
        Button {
            onDigit(label)
        } label: {
            Text(label)
                .font(.title2.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var deleteKey: some View {
        Button(action: onDelete) {
            Image(systemName: "delete.left")
                .font(.title3)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
