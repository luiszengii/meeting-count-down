import SwiftUI

/// `SettingsView` 是 Phase 0 的设置窗口占位。
/// 它的职责不是提供完整配置能力，而是提前把“活动数据源由协调层统一切换”的交互形态固定下来，
/// 让后续接入向导、偏好设置和诊断页都能继续复用这条状态流。
struct SettingsView: View {
    /// 设置窗口和菜单栏共享同一份协调层实例。
    @ObservedObject var sourceCoordinator: SourceCoordinator
    /// 本地缓存当前选中的模式，目的是把 Picker 的 UI 选择状态和协调层异步切换动作解耦。
    @State private var selectedMode: ConnectionMode

    /// 初始化时把当前激活模式同步到本地状态，避免设置页第一次打开时出现 Picker 和真实状态不一致。
    init(sourceCoordinator: SourceCoordinator) {
        self.sourceCoordinator = sourceCoordinator
        _selectedMode = State(initialValue: sourceCoordinator.state.activeMode)
    }

    /// SwiftUI 表单声明。
    /// 这里先把设置页当作“统一状态总览 + 模式切换入口”，后续再逐步长出真实配置项。
    var body: some View {
        /// 这里先把设置页固定成分组表单形态，后续新增接入配置和诊断项时可以继续沿用同一视觉结构。
        Form {
            Section("Phase 0 状态") {
                LabeledContent("当前活动模式", value: sourceCoordinator.state.activeMode.displayName)
                LabeledContent("健康状态", value: sourceCoordinator.state.healthState.summary)
                LabeledContent("最近刷新", value: sourceCoordinator.lastRefreshLine)
            }

            Section("活动数据源") {
                Picker("接入方式", selection: $selectedMode) {
                    ForEach(ConnectionMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                /// 切换模式时不直接改状态字段，而是把动作交给协调层统一处理。
                .onChange(of: selectedMode) { newValue in
                    Task {
                        await sourceCoordinator.activate(mode: newValue)
                    }
                }

                Text("这里先提供统一的切换入口，真实接入配置、权限检测和失败回退会在 Phase 1 接入。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("提醒偏好占位") {
                Text("倒计时秒数覆盖、静音模式、音效选择等偏好模型已经在代码层预留，但这一阶段还不写入真实持久化。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
