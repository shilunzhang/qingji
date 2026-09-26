import SwiftUI
import SwiftData

/// 自动入账记录（文档 F-12/F-14）：机器入账与防重跳过日志，已入账支持撤销
struct AutoPostLogView: View {
    @Environment(\.modelContext) private var context
    @ObservedObject private var store = AutoPostStore.shared

    var body: some View {
        List {
            if store.entries.isEmpty {
                EmptyStateView(icon: "tray",
                               title: "暂无自动入账记录",
                               hint: "配置自动截图识别后，每次自动处理（入账或防重跳过）都会记录在这里")
            }
            ForEach(store.entries) { entry in
                row(entry)
            }
        }
        .navigationTitle("自动入账记录")
    }

    @ViewBuilder
    private func row(_ entry: AutoPostEntry) -> some View {
        HStack(spacing: 10) {
            statusIcon(entry.status)

            VStack(alignment: .leading, spacing: 2) {
                Text(header(entry))
                    .font(.subheadline)
                Text(subheader(entry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            AmountText(entry.amountCents, kind: entry.kind, font: .subheadline.weight(.medium))

            if entry.status == .posted {
                Button("撤销") {
                    undo(entry)
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: AutoPostStatus) -> some View {
        switch status {
        case .posted:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.income)
        case .skippedDuplicate:
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Color.orange)
        case .undone:
            Image(systemName: "arrow.uturn.backward.circle")
                .foregroundStyle(.secondary)
        }
    }

    private func header(_ entry: AutoPostEntry) -> String {
        let amount = Money.string(fromCents: entry.amountCents)
        switch entry.status {
        case .posted:
            return "\(entry.kind.title) \(amount) · 已入账"
        case .skippedDuplicate:
            return "\(entry.kind.title) \(amount) · 疑似重复已跳过"
        case .undone:
            return "\(entry.kind.title) \(amount) · 已撤销"
        }
    }

    private func subheader(_ entry: AutoPostEntry) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 HH:mm"
        let trade = formatter.string(from: entry.date)
        if entry.note.isEmpty {
            return "交易时间 \(trade)"
        }
        return "\(entry.note) · 交易时间 \(trade)"
    }

    private func undo(_ entry: AutoPostEntry) {
        guard let txID = store.markUndone(entry.id) else { return }
        let all = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        if let tx = all.first(where: { $0.id == txID }) {
            context.delete(tx)
            try? context.save()
        }
    }
}
