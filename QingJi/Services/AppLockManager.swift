import Foundation
import LocalAuthentication
import SwiftUI

/// App 锁（文档 F-08）：开启后切后台即锁定，回前台需 Face ID/密码解锁。
@MainActor
final class AppLockManager: ObservableObject {

    @Published var isLocked = false
    @Published var biometryAvailable = false

    private let defaultsKey = "qingji.appLockEnabled"

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: defaultsKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
            if newValue { refreshAvailability() }
        }
    }

    func refreshAvailability() {
        let context = LAContext()
        var error: NSError?
        biometryAvailable = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    /// 场景切换处理
    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            if isEnabled { isLocked = true }
        case .active:
            if isLocked { authenticate() }
        default:
            break
        }
    }

    private func authenticate() {
        let context = LAContext()
        context.evaluatePolicy(.deviceOwnerAuthentication,
                               localizedReason: "解锁轻记，查看你的账目") { [weak self] success, _ in
            Task { @MainActor in
                if success {
                    self?.isLocked = false
                }
            }
        }
    }

    func unlockManually() {
        authenticate()
    }
}
