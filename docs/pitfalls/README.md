# Pitfalls

这个目录记录开发过程中需要反复排查、容易遗忘、未来大概率还会再次踩到的问题。

## 什么时候写 Pitfall

- 同一个问题在多个 session 里反复出现
- 排查过程明显比“改一行代码”复杂
- 问题与 Swift、SwiftUI、EventKit、OAuth、权限、并发或 macOS 生命周期相关
- 即使已经解决，未来没有文档就很难快速回忆

## 命名规则

- `kebab-case-title.md`

## 当前状态

- [xcodebuild 首次运行时插件加载失败](./xcodebuild-first-launch-plugin-failure.md)
- [EventKit 日历权限调试边界](./eventkit-calendar-permission-debugging.md)
- [unsigned DMG 在另一台 Mac 上无法稳定承接 Calendar 权限](./unsigned-dmg-calendar-permission-on-other-mac.md)
- [本地自签名 Code Signing 身份用于手动分发](./local-self-signed-code-signing-identity-for-manual-distribution.md)
- [Debug 和 Release 共用 bundle id 导致 Calendar 权限混淆](./shared-bundle-id-between-debug-and-release-confuses-calendar-permission.md)
- [自动生成的 Info.plist 在 release runner 上丢失 Calendar 权限说明](./generated-infoplist-missing-calendar-usage-description-on-release-runner.md)
- [MenuBarExtra label 使用 TimelineView 导致高频重绘](./swiftui-menubarextra-timelineview-overdraw.md)
- [SwiftUI Settings scene 在菜单栏 app 里的打开方式](./swiftui-settings-scene-in-menu-bar-app.md)
- [新增源文件后需要重新生成 Xcode 工程](./xcodegen-regenerate-project-after-adding-files.md)
