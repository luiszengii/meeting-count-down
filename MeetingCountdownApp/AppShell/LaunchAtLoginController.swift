import Foundation
import ServiceManagement

/// `LaunchAtLoginController` 负责把开机启动注册状态包装成设置页可直接消费的 ObservableObject。
/// 视图层不直接调用 `SMAppService`，避免把注册、错误恢复和状态文案散落在按钮里。
@MainActor
final class LaunchAtLoginController: ObservableObject {
    /// 当前开机启动开关是否应被视为“已启用或等待批准”。
    @Published private(set) var isEnabled: Bool
    /// 当前是否正在应用新的开机启动状态。
    @Published private(set) var isApplyingState: Bool
    /// 最近一次用户可见错误。
    @Published private(set) var lastErrorMessage: String?

    /// 当前 app 对应的登录项服务。
    /// `SMAppService` 本身不是 `Sendable`，但这里始终只在主线程 UI 控制器里使用。
    /// 把存储属性标成 `nonisolated(unsafe)`，是为了避免 Swift 6 在异步 API 调用时把它误判成跨 actor 发送。
    nonisolated(unsafe) private let service: SMAppService

    init(service: SMAppService = .mainApp, autoRefreshOnStart: Bool = true) {
        self.service = service
        self.isEnabled = Self.isEnabledStatus(service.status)
        self.isApplyingState = false
        self.lastErrorMessage = nil

        if autoRefreshOnStart {
            Task { [weak self] in
                await self?.refreshState()
            }
        }
    }

    /// 重新读取当前注册状态。
    func refreshState() async {
        isEnabled = Self.isEnabledStatus(service.status)
        lastErrorMessage = nil
    }

    /// 用户切换开机启动开关时的统一入口。
    func setEnabled(_ isEnabled: Bool) async {
        isApplyingState = true
        lastErrorMessage = nil

        defer {
            isApplyingState = false
            self.isEnabled = Self.isEnabledStatus(service.status)
        }

        do {
            if isEnabled {
                try service.register()
            } else {
                try await service.unregister()
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    /// 给设置页展示当前注册状态的解释文案。
    var statusSummary: String {
        statusSummary(for: .simplifiedChinese)
    }

    /// 开机启动状态同样需要跟随界面语言切换。
    func statusSummary(for language: AppUILanguage) -> String {
        switch service.status {
        case .enabled:
            return language == .english
                ? "The app will launch automatically after login."
                : "开机登录后会自动启动。"
        case .requiresApproval:
            return language == .english
                ? "macOS recorded the launch-at-login request, but it still needs approval in System Settings."
                : "系统已记录开机启动请求，但仍需要你在系统设置里批准。"
        case .notRegistered:
            return language == .english
                ? "The app will not launch automatically after login."
                : "当前不会在登录后自动启动。"
        case .notFound:
            return language == .english
                ? "Launch at login isn't available for the current installation."
                : "当前安装方式暂不支持开机启动。"
        @unknown default:
            return language == .english
                ? "The launch-at-login status could not be determined."
                : "无法确认开机启动状态。"
        }
    }

    /// `requiresApproval` 对用户来说仍应视为“我已经打开了这个可选项，只是系统还没批准”。
    private static func isEnabledStatus(_ status: SMAppService.Status) -> Bool {
        switch status {
        case .enabled, .requiresApproval:
            return true
        case .notRegistered, .notFound:
            return false
        @unknown default:
            return false
        }
    }
}
