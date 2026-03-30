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
