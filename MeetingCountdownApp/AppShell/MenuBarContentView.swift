import AppKit
import SwiftUI

/// `MenuBarContentView` 展示当前菜单栏应用能给用户看到的最小状态。
/// 这个视图只读取 `SourceCoordinatorState` 的聚合结果，不知道底层数据到底来自
/// 系统日历、飞书 API、离线导入还是 CLI。这样后续接入真实能力时，
/// 菜单栏层只需要跟随状态字段扩展，而不需要被具体实现反向污染。
struct MenuBarContentView: View {
    /// 视图只观察协调层，不直接依赖任何底层接入实现。
    @ObservedObject var sourceCoordinator: SourceCoordinator

    /// SwiftUI 通过 `body` 描述当前菜单内容应该如何由状态渲染出来。
    var body: some View {
        /// 外层垂直布局按“当前状态 -> 下一场会议 -> 操作按钮”的顺序组织，
        /// 让用户在菜单栏里先看状态，再看会议信息，最后决定是否手动操作。
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

            /// 所有手动刷新都统一走协调层的 `refresh(trigger:)`，避免视图直接操纵底层源。
            Button {
                Task {
                    await sourceCoordinator.refresh(trigger: .manualRefresh)
                }
            } label: {
                Label("立即刷新", systemImage: "arrow.clockwise")
            }
            .disabled(sourceCoordinator.state.isRefreshing)

            /// 最低版本已经提升到 macOS 14，因此这里回到系统推荐的 `SettingsLink`。
            SettingsLink {
                Label("打开设置", systemImage: "gearshape")
            }

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("退出", systemImage: "xmark.circle")
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}
