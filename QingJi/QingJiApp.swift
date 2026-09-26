import SwiftUI
import SwiftData

@main
struct QingJiApp: App {

    let container: ModelContainer

    init() {
        // 文档 D4：优先 CloudKit（.automatic），无 entitlement 时自动降级本地
        let cloudConfig = ModelConfiguration(cloudKitDatabase: .automatic)
        do {
            container = try ModelContainer(
                for: Transaction.self, Account.self, Category.self,
                Tag.self, Attachment.self, Budget.self, RecurringRule.self,
                configurations: cloudConfig)
        } catch {
            // 降级：纯本地存储（文档 §8 风险表）
            let localConfig = ModelConfiguration(cloudKitDatabase: .none)
            do {
                container = try ModelContainer(
                    for: Transaction.self, Account.self, Category.self,
                    Tag.self, Attachment.self, Budget.self, RecurringRule.self,
                    configurations: localConfig)
            } catch {
                fatalError("ModelContainer 初始化失败: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(container)
    }
}
