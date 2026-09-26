import Foundation
import SwiftData

/// 周期记账引擎（文档 F-07）：到期规则补成流水，lastPostedDate 幂等防重。
enum RecurringEngine {

    // MARK: - 纯函数： occurrence 推算

    /// 规则的第一次执行日（≥ startDate，落在天粒度）
    static func firstOccurrence(of rule: RecurringRule, calendar: Calendar = .current) -> Date? {
        let start = calendar.startOfDay(for: rule.startDate)
        switch rule.frequency {
        case .daily:
            return start
        case .weekly:
            // 一周内指定 weekday 的第一次出现（周一为每周第一天）
            let weekStart = DateHelpers.startOfWeek(start)
            let target = calendar.date(byAdding: .day, value: max(0, min(6, rule.weekday - 1)), to: weekStart) ?? start
            return target >= start ? target : calendar.date(byAdding: .day, value: 7, to: target)
        case .monthly:
            var current = start
            for _ in 0..<13 {
                let candidate = clampedMonthlyDate(from: current, day: rule.dayOfMonth, calendar: calendar)
                if let candidate, candidate >= start { return candidate }
                current = calendar.date(byAdding: .month, value: 1, to: current) ?? current
            }
            return nil
        case .yearly:
            var current = start
            for _ in 0..<3 {
                var comps = calendar.dateComponents([.year, .month], from: current)
                comps.day = rule.dayOfMonth == 0 ? 1 : rule.dayOfMonth
                if let candidate = calendar.date(from: comps), candidate >= start {
                    return candidate
                }
                current = calendar.date(byAdding: .year, value: 1, to: current) ?? current
            }
            return nil
        }
    }

    /// monthly 的「本月第 X 天」，超出月天数时收敛到月末
    private static func clampedMonthlyDate(from date: Date, day: Int, calendar: Calendar) -> Date? {
        var comps = calendar.dateComponents([.year, .month], from: date)
        let daysInMonth = DateHelpers.daysInMonth(of: date)
        comps.day = max(1, min(daysInMonth, day))
        return calendar.date(from: comps)
    }

    /// 从某次 occurrence 推下一次
    static func nextOccurrence(after date: Date, of rule: RecurringRule, calendar: Calendar = .current) -> Date? {
        let day = calendar.startOfDay(for: date)
        switch rule.frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: max(1, rule.intervalDays), to: day)
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: day)
        case .monthly:
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: day) ?? day
            return clampedMonthlyDate(from: nextMonth, day: rule.dayOfMonth, calendar: calendar)
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: day)
        }
    }

    /// 「after 之后（严格大于）」的下一次执行日；超过 endDate 或找不到返回 nil
    static func nextDueDate(of rule: RecurringRule, after: Date, calendar: Calendar = .current) -> Date? {
        guard let first = firstOccurrence(of: rule, calendar: calendar) else { return nil }
        var cursor = first
        var guardCounter = 0
        while cursor <= after {
            guard let next = nextOccurrence(after: cursor, of: rule, calendar: calendar) else { return nil }
            cursor = next
            guardCounter += 1
            if guardCounter > 100_000 { return nil } // 防御异常参数
        }
        if let end = rule.endDate, cursor > DateHelpers.endOfDay(end) { return nil }
        return cursor
    }

    // MARK: - 落账

    /// 把所有到期规则补成流水（多天没开 App 逐期补齐）。返回生成笔数。
    @discardableResult
    static func postDueRules(rules: [RecurringRule],
                             context: ModelContext,
                             upTo: Date = .now,
                             calendar: Calendar = .current) -> Int {
        let today = DateHelpers.endOfDay(upTo)
        var created = 0

        for rule in rules where rule.isActive {
            // 游标：上次已入账时间；从未入过账则从 startDate 前一天起
            var cursor: Date
            if let last = rule.lastPostedDate {
                cursor = last
            } else {
                cursor = calendar.startOfDay(for: rule.startDate).addingTimeInterval(-1)
            }
            guard today > cursor else { continue }

            var lastPosted = rule.lastPostedDate
            var guardCounter = 0
            while let due = nextDueDate(of: rule, after: cursor, calendar: calendar), due <= today {
                let tx = Transaction(kind: rule.kind,
                                     amountCents: rule.amountCents,
                                     date: due,
                                     account: rule.account,
                                     category: rule.category,
                                     note: rule.note,
                                     recurringRuleID: rule.id)
                context.insert(tx)
                lastPosted = due
                cursor = due
                created += 1
                guardCounter += 1
                if guardCounter > 100_000 { break } // 防御异常参数
            }
            if let lastPosted {
                rule.lastPostedDate = lastPosted
            }
        }
        if created > 0 { try? context.save() }
        return created
    }
}
