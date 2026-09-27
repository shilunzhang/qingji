import Foundation

/// 防重灵敏度（文档 F-14 第 5 道防线）
enum DuplicateSensitivity: String, CaseIterable, Identifiable {
    case off      // 关闭
    case confirm  // 提醒确认（默认）
    case block    // 阻止

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "关闭"
        case .confirm: return "提醒确认"
        case .block: return "阻止"
        }
    }
}

/// 疑似重复命中
struct DuplicateMatch: Identifiable {
    /// 命中的已有账目 id
    let id: UUID
    let kind: TxKind
    let amountCents: Int64
    let date: Date
    let title: String
    let source: TxSource
    let minutesApart: Int

    var summary: String {
        let prefix: String
        switch kind {
        case .expense: prefix = "-"
        case .income: prefix = "+"
        case .transfer: prefix = ""
        }
        return "\(prefix)\(Money.string(fromCents: amountCents))·\(title)·时间相差 \(minutesApart) 分钟"
    }
}

/// 统一防重闸门（文档 F-14 第 1 道防线）。
/// 所有入账入口（手动/OCR/相册/导入/通知/自动）保存前必须经过。
enum DuplicateGuard {

    static let defaultWindowMinutes = 10
    private static let sensitivityKey = "qingji.duplicate.sensitivity"

    /// 灵敏度（UserDefaults 持久化）
    static var sensitivity: DuplicateSensitivity {
        get {
            DuplicateSensitivity(rawValue: UserDefaults.standard.string(forKey: sensitivityKey) ?? "") ?? .confirm
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: sensitivityKey)
        }
    }

    /// 在已有账目中查找疑似重复（同方向 + 同金额 + 时间差 ≤ 窗口），取时间最接近的一条。
    /// - Parameters:
    ///   - excludeID: 编辑场景排除自身
    ///   - excludedSources: 忽略特定来源（导入第 3 层排除 .bill，避免误杀近距离真实账单行）
    static func findDuplicate(of kind: TxKind,
                              amountCents: Int64,
                              date: Date,
                              in transactions: [Transaction],
                              windowMinutes: Int = DuplicateGuard.defaultWindowMinutes,
                              excludeID: UUID? = nil,
                              excludedSources: Set<TxSource> = []) -> DuplicateMatch? {
        let window = TimeInterval(windowMinutes) * 60
        var best: (match: DuplicateMatch, gap: TimeInterval)?

        for tx in transactions {
            if let excludeID, tx.id == excludeID { continue }
            if excludedSources.contains(tx.txSource) { continue }
            guard tx.type == kind, tx.amountCents == amountCents else { continue }

            let gap = abs(tx.date.timeIntervalSince(date))
            guard gap <= window else { continue }

            let match = DuplicateMatch(id: tx.id,
                                       kind: kind,
                                       amountCents: amountCents,
                                       date: tx.date,
                                       title: tx.displayTitle,
                                       source: tx.txSource,
                                       minutesApart: Int(gap / 60))
            if best == nil || gap < best?.gap ?? .infinity {
                best = (match, gap)
            }
        }
        return best?.match
    }

    // MARK: - 决策

    enum ManualDecision {
        case allow
        case confirm(DuplicateMatch)
        case block(DuplicateMatch)
    }

    enum AutoDecision {
        case post
        case skip(DuplicateMatch)
    }

    /// 手动入口：关闭→直接保存；提醒确认→弹窗可强制；阻止→拒绝保存
    static func manualDecision(for match: DuplicateMatch?) -> ManualDecision {
        switch sensitivity {
        case .off:
            return .allow
        case .confirm:
            if let match { return .confirm(match) }
            return .allow
        case .block:
            if let match { return .block(match) }
            return .allow
        }
    }

    /// 自动入口：关闭→入账；其余档位疑似重复→跳过
    static func autoDecision(for match: DuplicateMatch?) -> AutoDecision {
        switch sensitivity {
        case .off:
            return .post
        case .confirm, .block:
            if let match { return .skip(match) }
            return .post
        }
    }
}

/// 截图指纹缓存（文档 F-14 第 2 道防线）。
/// 指纹 = 金额 + 页面交易时间(分) + 商户；同一支付页多张截图只处理一次；7 天过期。
enum ScreenshotFingerprintStore {

    private static let key = "qingji.screenshot.fingerprints"
    private static let expiryDays = 7

    static func fingerprint(amountCents: Int64, pageDate: Date?, merchant: String) -> String {
        let minute: Int
        if let pageDate {
            minute = Int(pageDate.timeIntervalSince1970 / 60)
        } else {
            minute = -1
        }
        return "\(amountCents)|\(minute)|\(merchant)"
    }

    static func contains(_ fingerprint: String, now: Date = .now, defaults: UserDefaults = .standard) -> Bool {
        purge(now: now, defaults: defaults)
        return store(defaults: defaults)?.keys.contains(fingerprint) ?? false
    }

    static func insert(_ fingerprint: String, now: Date = .now, defaults: UserDefaults = .standard) {
        var dict = store(defaults: defaults) ?? [:]
        dict[fingerprint] = now.timeIntervalSince1970
        defaults.set(dict, forKey: key)
    }

    static func purge(now: Date = .now,
                      defaults: UserDefaults = .standard,
                      expiryDays: Int = ScreenshotFingerprintStore.expiryDays) {
        guard var dict = store(defaults: defaults), !dict.isEmpty else { return }
        let cutoff = now.timeIntervalSince1970 - TimeInterval(expiryDays) * 86_400
        let before = dict.count
        dict = dict.filter { $0.value >= cutoff }
        if dict.count != before {
            defaults.set(dict, forKey: key)
        }
    }

    /// 当前缓存条数（诊断页用）
    static func count(defaults: UserDefaults = .standard) -> Int {
        store(defaults: defaults)?.count ?? 0
    }

    private static func store(defaults: UserDefaults) -> [String: Double]? {
        defaults.dictionary(forKey: key) as? [String: Double]
    }
}
