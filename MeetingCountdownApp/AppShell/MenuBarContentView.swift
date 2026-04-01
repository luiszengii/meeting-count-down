import AppKit
import SwiftUI

/// `MenuBarLabelView` 是真正出现在系统菜单栏里的那块小标签。
/// 它同时观察会议读取状态和提醒状态：平时展示下一场会议倒计时，
/// 一旦提醒真正命中，就临时切换成更明显的图标与短文案，作为不依赖通知权限的可见提醒兜底。
struct MenuBarLabelView: View {
    /// 菜单栏默认标题仍然来自会议读取协调层。
    @ObservedObject var sourceCoordinator: SourceCoordinator
    /// 提醒命中时的高优先级视觉状态来自提醒引擎。
    @ObservedObject var reminderEngine: ReminderEngine

    var body: some View {
        let presentation = currentPresentation()

        HStack(spacing: presentation.isHighPriority ? 5 : 4) {
            Image(systemName: presentation.symbolName)
                .font(.system(size: presentation.isHighPriority ? 13 : 12, weight: presentation.isHighPriority ? .bold : .semibold))

            Text(presentation.title)
                .font(
                    .system(
                        size: 12,
                        weight: presentation.isHighPriority ? .black : .semibold,
                        design: .rounded
                    )
                )
                .lineLimit(1)
        }
        .monospacedDigit()
    }

    /// 提醒命中时优先展示提醒态，否则沿用普通菜单栏标题。
    private func currentPresentation() -> ReminderMenuBarAlertPresentation {
        reminderEngine.state.menuBarAlertPresentation()
            ?? ReminderMenuBarAlertPresentation(
                title: sourceCoordinator.menuBarTitle,
                symbolName: sourceCoordinator.menuBarSymbolName,
                isHighPriority: false
            )
    }
}

/// `MenuBarContentView` 展示当前菜单栏应用能给用户看到的最小状态。
/// 这个视图只读取 `SourceCoordinatorState` 和 `ReminderState` 的聚合结果，
/// 不直接接触 EventKit 或底层调度任务，避免菜单层自己重新实现业务规则。
struct MenuBarContentView: View {
    /// 菜单内容需要观察会议读取状态。
    @ObservedObject var sourceCoordinator: SourceCoordinator
    /// 菜单内容同样需要观察提醒状态，告诉用户是否已经安排好提醒。
    @ObservedObject var reminderEngine: ReminderEngine
    /// 共享的设置窗口控制器负责把已存在的设置页窗口拉回前台。
    let settingsWindowController: SettingsWindowController
    /// SwiftUI 官方提供的设置窗口打开动作。
    @Environment(\.openSettings) private var openSettings

    /// SwiftUI 通过 `body` 描述当前菜单内容应该如何由状态渲染出来。
    var body: some View {
        /// 外层垂直布局按“当前状态 -> 下一场会议 -> 提醒状态 -> 操作按钮”的顺序组织，
        /// 让用户在菜单栏里先看读会结果，再看提醒有没有真正建立。
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(sourceCoordinator.state.primaryStatusLine)
                    .font(.headline)

                Text(sourceCoordinator.detailLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            /// 当存在下一场会议时，优先展示具体会议；否则退回到明确的空状态提示。
            if let nextMeeting = sourceCoordinator.state.nextMeeting {
                VStack(alignment: .leading, spacing: 4) {
                    Text("下一场会议")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(nextMeeting.title)
                        .font(.body.weight(.medium))

                    Text(sourceCoordinator.meetingStartLine(for: nextMeeting))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("当前没有可用于提醒的会议。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            /// 提醒状态单独占一块，帮助用户区分“读到会议了”和“提醒真的已经安排上了”。
            VStack(alignment: .leading, spacing: 4) {
                Text("提醒状态")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(reminderEngine.state.summary)
                    .font(.body.weight(.medium))

                Text(reminderEngine.state.detailLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            /// 所有手动刷新都统一走协调层的 `refresh(trigger:)`，避免视图直接操纵底层源。
            Button {
                Task {
                    await sourceCoordinator.refresh(trigger: .manualRefresh)
                }
            } label: {
                Label("立即刷新", systemImage: "arrow.clockwise")
            }
            .disabled(sourceCoordinator.state.isRefreshing)

            /// 这里仍然走 SwiftUI 官方支持的 `openSettings()`，
            /// 只是额外在打开后把已知设置窗口显式提到最前，修复菜单栏应用容易被其它 app 压住的问题。
            Button {
                openSettingsWindow()
            } label: {
                Label("打开设置", systemImage: "gearshape")
            }

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("退出", systemImage: "xmark.circle")
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    /// 显式打开设置窗口并把它提升到前台，避免菜单栏 app 的设置页落在其它窗口后面。
    private func openSettingsWindow() {
        settingsWindowController.requestWindowActivation()
        NSApplication.shared.activate(ignoringOtherApps: true)
        openSettings()
    }
}
