import SwiftUI
import SwiftData
import UIKit
import UserNotifications

/// 全局数据库容器：App 界面与「截图入账」App Intent（后台运行）共用
enum AppDatabase {
    static let shared: ModelContainer = {
        // 文档 D4：优先 CloudKit（.automatic），无 entitlement 时自动降级本地
        let cloudConfig = ModelConfiguration(cloudKitDatabase: .automatic)
        do {
            return try ModelContainer(for: Transaction.self, Account.self, Category.self,
                                      Tag.self, Attachment.self, Budget.self, RecurringRule.self,
                                      configurations: cloudConfig)
        } catch {
            let localConfig = ModelConfiguration(cloudKitDatabase: .none)
            do {
                return try ModelContainer(for: Transaction.self, Account.self, Category.self,
                                          Tag.self, Attachment.self, Budget.self, RecurringRule.self,
                                          configurations: localConfig)
            } catch {
                fatalError("ModelContainer 初始化失败: \(error)")
            }
        }
    }()
}

@main
struct QingJiApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(AppDatabase.shared)
    }
}

/// 通知代理：处理「截图入账」确认卡的按钮回调（文档 F-12）
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        CaptureNotificationHandler.registerCategories()
        return true
    }

    /// 前台时也横幅显示确认卡
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        guard notification.request.content.categoryIdentifier == CaptureNotificationHandler.categoryIdentifier else {
            return []
        }
        return [.banner, .list, .sound]
    }

    /// 用户点了「入账 / 忽略」
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard response.notification.request.content.categoryIdentifier == CaptureNotificationHandler.categoryIdentifier else {
            return
        }
        await CaptureNotificationHandler.handle(actionIdentifier: response.actionIdentifier,
                                                notificationID: response.notification.request.identifier)
    }
}
