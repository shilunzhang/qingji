import Foundation

/// 消费渠道（文档 v1.4 新增）
/// 版权安全：不使用任何品牌 Logo 图片，仅用通用 SF Symbol + 品牌主色区分
enum TxChannel: String, Codable, CaseIterable {
    case alipay
    case wechat
    case bank
    case unionpay
    case unknown

    var title: String {
        switch self {
        case .alipay: return "支付宝"
        case .wechat: return "微信"
        case .bank: return "银行卡"
        case .unionpay: return "云闪付"
        case .unknown: return "其他"
        }
    }

    var icon: String {
        switch self {
        case .alipay: return "qrcode"
        case .wechat: return "message"
        case .bank: return "building.columns"
        case .unionpay: return "creditcard"
        case .unknown: return "questionmark.circle"
        }
    }

    /// 品牌主色（仅作颜色区分，非商标）
    var colorHex: String {
        switch self {
        case .alipay: return "1677FF"
        case .wechat: return "07C160"
        case .bank: return "1B5EAB"
        case .unionpay: return "D5281E"
        case .unknown: return "8E8E93"
        }
    }

    /// 渠道对应的默认账户类型（自动选账户用）
    var accountKind: AccountKind? {
        switch self {
        case .alipay: return .alipay
        case .wechat: return .wechat
        case .bank: return .bank
        case .unionpay: return .bank
        case .unknown: return nil
        }
    }
}

/// 从 OCR 文本/支付方式名识别渠道
enum ChannelDetector {

    static func detect(_ text: String) -> TxChannel {
        let t = text.lowercased()
        // 顺序即优先级：支付宝特征最独特，先判
        if t.contains("支付宝") || t.contains("alipay") || t.contains("余额宝") || t.contains("花呗") {
            return .alipay
        }
        if t.contains("微信") || t.contains("wechat") || t.contains("零钱") {
            return .wechat
        }
        if t.contains("云闪付") || t.contains("unionpay") {
            return .unionpay
        }
        if t.contains("银行") || t.contains("储蓄卡") || t.contains("信用卡")
            || t.contains("借记卡") || t.contains("网银") {
            return .bank
        }
        return .unknown
    }
}
