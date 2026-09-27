import SwiftUI

/// 流水行（明细页 / 日历页复用）
struct TransactionRowView: View {
    let tx: Transaction

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(icon: iconName, colorHex: colorHex)

            VStack(alignment: .leading, spacing: 2) {
                Text(tx.displayTitle)
                    .font(.subheadline.weight(.medium))
                if !tx.note.isEmpty {
                    Text(tx.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let channel = tx.channelInfo {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(Color(hex: channel.colorHex))
                            .frame(width: 5, height: 5)
                        Text(channel.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                AmountText(tx.amountCents, kind: tx.type)
                if tx.hasDiscount {
                    Text("原价 \(Money.string(fromCents: tx.originalAmountCents))")
                        .font(.caption2)
                        .strikethrough()
                        .foregroundStyle(.tertiary)
                }
                if tx.type == .transfer {
                    Text("\(tx.account?.name ?? "") → \(tx.toAccount?.name ?? "")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var iconName: String {
        if tx.type == .transfer { return "arrow.left.arrow.right" }
        if let cat = tx.category { return cat.icon }
        if let account = tx.account { return account.icon }
        return "ellipsis"
    }

    private var colorHex: String {
        if tx.type == .transfer { return tx.account?.colorHex ?? "007AFF" }
        if let cat = tx.category { return cat.colorHex }
        if let account = tx.account { return account.colorHex }
        return "9E9E9E"
    }
}
