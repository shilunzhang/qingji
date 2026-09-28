import SwiftUI

/// 分类/账户圆形图标
struct IconBadge: View {
    let icon: String
    let colorHex: String
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.45, weight: .medium))
            .foregroundStyle(Color(hex: colorHex))
            .frame(width: size, height: size)
            .background(Color.categoryBackground(colorHex))
            .clipShape(Circle())
    }
}

/// 金额文本（文档 6.3 展示约定）：支出 - / 收入 + / 转账无符号
struct AmountText: View {
    let cents: Int64
    let kind: TxKind
    var font: Font = .subheadline.weight(.semibold)

    init(_ cents: Int64, kind: TxKind, font: Font = .body.weight(.medium)) {
        self.cents = cents
        self.kind = kind
        self.font = font
    }

    var color: Color {
        switch kind {
        case .income: return Theme.income
        case .transfer: return Theme.transfer
        case .expense: return .primary
        }
    }

    var body: some View {
        Text(displayString)
            .font(font)
            .foregroundStyle(color)
            .monospacedDigit()
    }

    var displayString: String {
        switch kind {
        case .expense: return "-" + Money.string(fromCents: cents)
        case .income: return "+" + Money.string(fromCents: cents)
        case .transfer: return Money.string(fromCents: cents)
        }
    }
}

/// 空态占位
struct EmptyStateView: View {
    let icon: String
    let title: String
    let hint: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(hint)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

/// 月份/周期切换导航头
struct PeriodNavHeader: View {
    let title: String
    let onPrev: () -> Void
    let onNext: () -> Void

    var body: some View {
        // v1.4.6：箭头紧贴标题（此前左右 Spacer 把箭头推到两端，视觉割裂）
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            Button(action: onPrev) {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("上一月")

            Text(title)
                .font(.headline)

            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("下一月")
            Spacer(minLength: 0)
        }
    }
}

/// 收支汇总条
struct TotalsBar: View {
    let expenseCents: Int64
    let incomeCents: Int64

    var balanceCents: Int64 { incomeCents - expenseCents }

    var body: some View {
        HStack(spacing: 0) {
            totalItem(label: "支出", cents: expenseCents, color: .primary, emphasized: true)
            totalItem(label: "收入", cents: incomeCents, color: Theme.income, emphasized: false)
            totalItem(label: "结余", cents: balanceCents, color: balanceCents >= 0 ? .primary : Theme.alert, emphasized: false)
        }
    }

    private func totalItem(label: String, cents: Int64, color: Color, emphasized: Bool) -> some View {
        // v1.4.9：三列各自居中；大数字单行 + 最低缩到 0.5 防挤压重叠
        VStack(alignment: .center, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(Money.string(fromCents: cents))
                .font(emphasized ? .title3.weight(.bold) : .headline)
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
