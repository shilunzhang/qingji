import SwiftUI
import SwiftData
import Charts

/// 统计页（文档 F-03）：日/周/月/年 × 支出/收入，饼图 + 趋势 + 分类排行
struct StatsView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    @State private var period: StatsPeriod = .month
    @State private var anchor = Date()
    @State private var kind: TxKind = .expense

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    controlSection
                    summaryCard
                    pieCard
                    trendCard
                    rankCard
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            // v1.4.7：去除页面大标题，导航栏隐藏
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - 数据

    private var range: (start: Date, end: Date) {
        DateHelpers.range(of: period, containing: anchor)
    }

    private var rangeTx: [Transaction] {
        LedgerService.transactions(transactions, in: range)
    }

    private var total: Int64 { StatsService.totalCents(rangeTx, kind: kind) }
    private var oppositeTotal: Int64 {
        StatsService.totalCents(rangeTx, kind: kind == .expense ? .income : .expense)
    }
    private var categoryStats: [CategoryStat] { StatsService.byCategory(rangeTx, kind: kind) }

    private var dailyAverage: Int64 {
        let calendar = Calendar.current
        let days = max(1, (calendar.dateComponents([.day],
                                                   from: range.start,
                                                   to: range.end).day ?? 0) + 1)
        return total / Int64(days)
    }

    // MARK: - 视图

    private var controlSection: some View {
        VStack(spacing: 10) {
            Picker("粒度", selection: $period) {
                ForEach(StatsPeriod.allCases) { p in
                    Text(p.title).tag(p)
                }
            }
            .pickerStyle(.segmented)

            PeriodNavHeader(
                title: DateHelpers.title(of: period, for: anchor),
                onPrev: { anchor = DateHelpers.shift(anchor, by: -1, of: period) },
                onNext: { anchor = DateHelpers.shift(anchor, by: 1, of: period) }
            )

            Picker("方向", selection: $kind) {
                Text("支出").tag(TxKind.expense)
                Text("收入").tag(TxKind.income)
            }
            .pickerStyle(.segmented)
        }
        .card()
    }

    private var summaryCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(kind == .expense ? "总支出" : "总收入")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Money.string(fromCents: total))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("日均")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Money.string(fromCents: dailyAverage))
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                Text((kind == .expense ? "同期收入 " : "同期支出 ") + Money.string(fromCents: oppositeTotal))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .card()
    }

    private var pieCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("分类构成")
                .font(.subheadline.weight(.medium))
            let slices = StatsService.pieSlices(categoryStats)
            if slices.isEmpty {
                EmptyStateView(icon: "chart.pie",
                               title: "暂无\(kind.title)数据",
                               hint: "换个时间范围看看，或先记几笔")
            } else {
                Chart(slices) { slice in
                    SectorMark(angle: .value("金额", Double(slice.totalCents)),
                               innerRadius: .ratio(0.62),
                               angularInset: 1.5)
                        .cornerRadius(4)
                        .foregroundStyle(Color(hex: slice.colorHex))
                }
                .frame(height: 190)
                .overlay {
                    VStack(spacing: 2) {
                        Text(kind.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(Money.string(fromCents: total))
                            .font(.headline)
                            .monospacedDigit()
                            .minimumScaleFactor(0.5)
                            .padding(.horizontal, 40)
                    }
                }
            }
        }
        .card()
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("趋势")
                .font(.subheadline.weight(.medium))
            let totals = StatsService.byDay(rangeTx, kind: kind, in: range)
            if totals.isEmpty {
                EmptyStateView(icon: "chart.bar",
                               title: "暂无趋势数据",
                               hint: "该时间段内没有\(kind.title)记录")
            } else {
                Chart(totals) { item in
                    BarMark(
                        x: .value("日期", item.date, unit: period == .year ? .month : .day),
                        y: .value("金额", Double(item.totalCents))
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.75))
                    .cornerRadius(2)
                }
                .chartYAxis {
                    AxisMarks(position: .trailing)
                }
                .frame(height: 160)
            }
        }
        .card()
    }

    private var rankCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("分类排行")
                .font(.subheadline.weight(.medium))
            if categoryStats.isEmpty {
                EmptyStateView(icon: "list.number",
                               title: "暂无排行",
                               hint: "该时间段内没有\(kind.title)记录")
            } else {
                let maxCents = categoryStats.first?.totalCents ?? 1
                ForEach(categoryStats) { stat in
                    HStack(spacing: 10) {
                        IconBadge(icon: stat.icon, colorHex: stat.colorHex, size: 32)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(stat.name)
                                    .font(.subheadline)
                                Spacer()
                                Text(Money.string(fromCents: stat.totalCents))
                                    .font(.subheadline.weight(.medium))
                                    .monospacedDigit()
                            }
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color(uiColor: .tertiarySystemFill))
                                    Capsule()
                                        .fill(Color(hex: stat.colorHex))
                                        .frame(width: proxy.size.width * CGFloat(stat.totalCents) / CGFloat(maxCents))
                                }
                            }
                            .frame(height: 5)
                            HStack {
                                Spacer()
                                Text(String(format: "%.1f%%", stat.percent * 100))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }
        }
        .card()
    }
}
