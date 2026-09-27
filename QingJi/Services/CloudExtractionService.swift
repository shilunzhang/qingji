import Foundation

/// 云端大模型配置（用户自带 Key，OpenAI 兼容接口；默认关闭，文档 ADR D15 补充）
struct CloudAIConfig: Codable, Equatable {
    var enabled: Bool = false
    var baseURL: String = "https://api.deepseek.com/v1"
    var apiKey: String = ""
    var model: String = "deepseek-chat"

    var isConfigured: Bool {
        enabled && !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
            && !baseURL.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

enum CloudAIStore {
    private static let key = "qingji.cloudai.config"

    static func load(defaults: UserDefaults = .standard) -> CloudAIConfig {
        guard let data = defaults.data(forKey: key),
              let config = try? JSONDecoder().decode(CloudAIConfig.self, from: data) else {
            return CloudAIConfig()
        }
        return config
    }

    static func save(_ config: CloudAIConfig, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: key)
        }
    }
}

/// 云端结构化抽取（文档 F-12 语义层的云端档）
enum CloudExtractionService {

    struct Preset: Identifiable {
        let id: String
        let title: String
        let baseURL: String
        let model: String
        let note: String
    }

    static let presets: [Preset] = [
        Preset(id: "deepseek", title: "DeepSeek", baseURL: "https://api.deepseek.com/v1",
               model: "deepseek-chat", note: "platform.deepseek.com 申请 Key，费用极低"),
        Preset(id: "zhipu", title: "智谱 GLM", baseURL: "https://open.bigmodel.cn/api/paas/v4",
               model: "glm-4-flash", note: "open.bigmodel.cn 申请 Key，glm-4-flash 免费"),
        Preset(id: "qwen", title: "阿里云百炼 Qwen", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
               model: "qwen-plus", note: "bailian.console.aliyun.com 申请 Key"),
    ]

    /// 抽取；失败返回 nil（调用方回退下一层），成功返回交易行（可为空数组）
    static func extract(text: String, config: CloudAIConfig, now: Date = .now) async -> [PaymentTextParser.ParsedPayment]? {
        guard config.isConfigured else { return nil }

        let endpoint = config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            + "/chat/completions"
        guard let url = URL(string: endpoint) else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let system = SmartExtractionService.extractionInstructions(now: now)
            + "\n只输出一个 JSON 对象，格式：{\"transactions\":[{\"amount\":45.6,\"direction\":\"expense\",\"time\":\"2026-09-26 12:30\",\"merchant\":\"商户名\",\"note\":\"备注\"}]}，不要输出任何其他文字。"
        let body: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": String(text.prefix(2500))],
            ],
            "temperature": 0.1,
            "stream": false,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else {
            return nil
        }
        guard http.statusCode == 200 else { return nil }

        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = payload["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            return nil
        }
        return parseJSONContent(content, now: now)
    }

    /// 解析模型返回的 JSON（容忍 ```json 围栏）
    static func parseJSONContent(_ content: String, now: Date) -> [PaymentTextParser.ParsedPayment]? {
        var jsonString = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if jsonString.hasPrefix("```") {
            jsonString = jsonString
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = jsonString.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(CloudTransactionList.self, from: data) else {
            return nil
        }
        return decoded.transactions.compactMap { item in
            guard let cents = SmartExtractionService.centsFrom(item.amount), cents > 0 else { return nil }
            let kind: TxKind = item.direction?.lowercased() == "income" ? .income : .expense
            let date = item.time.flatMap { SmartExtractionService.parseTime($0, fallback: now) }
            return PaymentTextParser.ParsedPayment(amountCents: cents,
                                 date: date,
                                 counterparty: (item.merchant?.isEmpty == false) ? item.merchant! : "支付",
                                 kind: kind,
                                 note: (item.note?.isEmpty == false) ? item.note : nil)
        }
    }
}

struct CloudTransaction: Codable {
    let amount: Double
    var direction: String?
    var time: String?
    var merchant: String?
    var note: String?
}

struct CloudTransactionList: Codable {
    var transactions: [CloudTransaction]
}
