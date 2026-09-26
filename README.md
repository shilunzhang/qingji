# 轻记（QingJi）

轻松省心的 iOS 记账 App。产品与技术方案见 **[docs/开发文档.md](docs/开发文档.md)**（唯一事实来源）。

## 技术栈
SwiftUI · SwiftData (+CloudKit 自动同步) · Swift Charts · iOS 18+ · 零第三方依赖 · 金额以「分」(Int64) 存储

## 构建（需要 macOS）
```bash
brew install xcodegen
xcodegen generate          # 由 project.yml 生成 QingJi.xcodeproj
open QingJi.xcodeproj      # Xcode 中 Cmd+R 运行
```

## 测试
```bash
xcodebuild test -project QingJi.xcodeproj -scheme QingJi \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```
推送/PR 会自动触发 GitHub Actions（macOS runner）执行同样流程。

## iCloud 同步说明
工程使用 `ModelConfiguration(cloudKitDatabase: .automatic)`：
- 有 CloudKit entitlement（付费开发者账号 + iCloud 容器）→ 自动云同步
- 无 → 自动降级为纯本地存储，功能不受影响

## 目录
```
QingJi/            App 源码（Models / Services / Features / Components / Utilities）
QingJiTests/       单元测试
docs/              开发文档
project.yml        XcodeGen 工程定义
```
