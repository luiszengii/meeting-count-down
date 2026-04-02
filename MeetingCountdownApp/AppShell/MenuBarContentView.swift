import AppKit
import SwiftUI

/// `MenuBarContentView` 展示当前菜单栏应用能给用户看到的最小状态。
/// 这个视图只读取 `SourceCoordinatorState` 和 `ReminderState` 的聚合结果，
/// 不直接接触 EventKit 或底层调度任务，避免菜单层自己重新实现业务规则。
struct MenuBarContentView: View {
    /// 菜单内容需要观察会议读取状态。
    @ObservedObject var sourceCoordinator: SourceCoordinator
    /// 菜单内容同样需要观察提醒状态，告诉用户是否已经安排好提醒。
    @ObservedObject var reminderEngine: ReminderEngine
    /// 真正打开设置窗口的动作改成由外部显式注入，方便 `NSStatusItem` 和 SwiftUI 场景共用。
    let openSettingsAction: () -> Void

    /// SwiftUI 通过 `body` 描述当前菜单内容应该如何由状态渲染出来。
    var body: some View {
        /// 外层垂直布局按“下一场会议 / 空状态 -> 提醒状态 -> 操作按钮”的顺序组织。
        /// 当已经读到下一场会议时，不再重复把同一标题在顶部再显示一遍，避免弹层里出现两块内容表达同一场会议。
        VStack(alignment: .leading, spacing: 12) {
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
                VStack(alignment: .leading, spacing: 4) {
                    Text(sourceCoordinator.state.primaryStatusLine)
                        .font(.headline)

                    Text(sourceCoordinator.detailLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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

            /// “打开设置”改成走外部注入动作。
            /// 这样 `MenuBarContentView` 就不再依赖 `MenuBarExtra` 独有的环境值，
            /// 既能被 `NSPopover` 承载，也能继续共享已有的设置窗口前台化逻辑。
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

    /// 设置按钮只负责把动作继续交给外部。
    /// 真正的窗口创建和前台化都由壳层控制器统一处理，避免视图自己知道 AppKit 细节。
    private func openSettingsWindow() {
        openSettingsAction()
    }
}
