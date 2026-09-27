import SwiftUI
import SwiftData
import UserNotifications
import Photos
import UIKit

/// 诊断页（自动记账链路可观测性）：权限、处理状态、Intent 运行日志一目了然
struct DiagnosticsView: View {

    @State private var notificationStatus = "查询中…"
    @State private var photoStatus = "查询中…"
    @State private var modelStatus = "查询中…"
    @State private var processedCount = 0
    @State private var fingerprintCount = 0
    @State private var pendingCount = 0
    @State private var lastScan = "从未扫描"
    @State private var logLines: [String] = []

    var body: some View {
        List {
            Section("权限") {
                row("通知权限", value: notificationStatus)
                row("照片权限", value: photoStatus)
                row("端侧大模型", value: modelStatus)
            }

            Section("处理状态") {
                row("已处理截图", value: "\(processedCount) 张")
                row("截图指纹缓存", value: "\(fingerprintCount) 条")
                row("待确认账目", value: "\(pendingCount) 笔")
                row("上次相册扫描", value: lastScan)
                row("静默自动入账", value: CaptureSettings.autoSave ? "已开启" : "关闭（确认式）")
                row("防重灵敏度", value: DuplicateGuard.sensitivity.title)
            }

            Section("截图入账运行日志（最近 20 条）") {
                if logLines.isEmpty {
                    Text("暂无记录。配置快捷指令自动化并触发后，这里会显示每一步的执行结果")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(logLines, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 12, design: .monospaced))
                }
            }

            Section {
                Button("刷新") { refresh() }
                Button("清空运行日志", role: .destructive) { DiagLog.clear(); refresh() }
            }
        }
        .navigationTitle("诊断信息")
        .onAppear(perform: refresh)
    }

    private func refresh() {
        processedCount = AlbumScanStore.processedIDs().count
        fingerprintCount = ScreenshotFingerprintStore.count()
        lastScan = AlbumScanStore.lastScanDate().map {
            let formatter = DateFormatter()
            formatter.dateFormat = "M月d日 HH:mm"
            return formatter.string(from: $0)
        } ?? "从未扫描"
        logLines = DiagLog.lines()

        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            let names: [UNAuthorizationStatus: String] = [
                .notDetermined: "未询问", .denied: "已拒绝（去系统设置开启）",
                .authorized: "已允许", .provisional: "临时允许", .ephemeral: "已允许",
            ]
            notificationStatus = names[settings.authorizationStatus] ?? "未知"

            let photoNames: [PHAuthorizationStatus: String] = [
                .notDetermined: "未询问", .denied: "已拒绝（去系统设置开启）",
                .restricted: "受限制", .authorized: "已允许", .limited: "有限访问",
            ]
            photoStatus = photoNames[PHPhotoLibrary.authorizationStatus(for: .readWrite)] ?? "未知"

            modelStatus = SmartExtractionService.isAvailable ? "可用（语义抽取已启用）" : "不可用（走规则解析）"

            let pending = await MainActor.run { PendingCaptureStore.shared.count() }
            pendingCount = pending
        }
    }

    private func row(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
    }
}

/// 轻量运行日志（UserDefaults，最近 50 条）
enum DiagLog {
    private static let key = "qingji.diag.log"
    private static let capacity = 50

    static func append(_ line: String) {
        var logs = UserDefaults.standard.stringArray(forKey: key) ?? []
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        logs.insert("\(formatter.string(from: .now)) \(line)", at: 0)
        if logs.count > capacity {
            logs = Array(logs.prefix(capacity))
        }
        UserDefaults.standard.set(logs, forKey: key)
    }

    static func lines() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
