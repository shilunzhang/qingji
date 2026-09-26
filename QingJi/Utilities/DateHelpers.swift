import Foundation

/// 统计区间粒度
enum StatsPeriod: String, CaseIterable, Identifiable {
    case day, week, month, year
    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return "日"
        case .week: return "周"
        case .month: return "月"
        case .year: return "年"
        }
    }
}

/// 日期区间工具（M1 全部基于当前日历/时区）
enum DateHelpers {

    static var cal: Calendar { Calendar.current }

    // MARK: - 边界

    static func startOfDay(_ date: Date) -> Date {
        cal.startOfDay(for: date)
    }

    static func endOfDay(_ date: Date) -> Date {
        var comps = DateComponents()
        comps.day = 1
        comps.second = -1
        return cal.date(byAdding: comps, to: startOfDay(date)) ?? date
    }

    /// 区间 [start, end]，end 为该粒度最后一天 23:59:59
    static func range(of period: StatsPeriod, containing date: Date) -> (start: Date, end: Date) {
        switch period {
        case .day:
            return (startOfDay(date), endOfDay(date))
        case .week:
            let start = startOfWeek(date)
            let end = cal.date(byAdding: DateComponents(day: 6), to: start) ?? date
            return (start, endOfDay(end))
        case .month:
            let start = startOfMonth(date)
            let end = cal.date(byAdding: DateComponents(month: 1, second: -1), to: start) ?? date
            return (start, end)
        case .year:
            let start = startOfYear(date)
            let end = cal.date(byAdding: DateComponents(year: 1, second: -1), to: start) ?? date
            return (start, end)
        }
    }

    /// 周一为一周开始（文档 6.1，中文记账习惯）
    static func startOfWeek(_ date: Date) -> Date {
        let day = startOfDay(date)
        let weekday = cal.component(.weekday, from: day) // 1=周日 ... 7=周六
        let offset = (weekday + 5) % 7                    // 周一 -> 0
        return cal.date(byAdding: DateComponents(day: -offset), to: day) ?? day
    }

    static func startOfMonth(_ date: Date) -> Date {
        let comps = cal.dateComponents([.year, .month], from: date)
        return cal.date(from: comps) ?? startOfDay(date)
    }

    static func startOfYear(_ date: Date) -> Date {
        let year = cal.component(.year, from: date)
        return cal.date(from: DateComponents(year: year, month: 1, day: 1)) ?? startOfDay(date)
    }

    /// 上一个/下一个粒度区间锚点（保持锚点在天粒度移动）
    static func shift(_ date: Date, by periods: Int, of period: StatsPeriod) -> Date {
        let comps: DateComponents
        switch period {
        case .day: comps = DateComponents(day: periods)
        case .week: comps = DateComponents(day: 7 * periods)
        case .month: comps = DateComponents(month: periods)
        case .year: comps = DateComponents(year: periods)
        }
        return cal.date(byAdding: comps, to: date) ?? date
    }

    /// 月历网格：给定月份，返回 42 个格子的日期（含前后月补位），周一起始
    static func calendarGrid(forMonthOf date: Date) -> [Date] {
        let first = startOfMonth(date)
        let weekday = cal.component(.weekday, from: first)
        let offset = (weekday + 5) % 7
        let gridStart = cal.date(byAdding: DateComponents(day: -offset), to: first) ?? first
        return (0..<42).compactMap { cal.date(byAdding: DateComponents(day: $0), to: gridStart) }
    }

    static func daysInMonth(of date: Date) -> Int {
        cal.range(of: .day, in: .month, for: date)?.count ?? 30
    }

    // MARK: - 展示

    static func title(of period: StatsPeriod, for date: Date) -> String {
        let y = cal.component(.year, from: date)
        switch period {
        case .day:
            let m = cal.component(.month, from: date)
            let d = cal.component(.day, from: date)
            return "\(y)年\(m)月\(d)日"
        case .week:
            let start = startOfWeek(date)
            let end = cal.date(byAdding: DateComponents(day: 6), to: start) ?? date
            let f = DateFormatter()
            f.dateFormat = "M.d"
            return "\(f.string(from: start)) - \(f.string(from: end))"
        case .month:
            let m = cal.component(.month, from: date)
            return "\(y)年\(m)月"
        case .year:
            return "\(y)年"
        }
    }

    static let weekdayTitles = ["一", "二", "三", "四", "五", "六", "日"]
}
