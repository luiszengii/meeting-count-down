import SwiftUI

// MARK: - Standalone localization free function

/// 给独立 View struct 用的本地化入口；T7 i18n 落地后会把这里替换为 key-based。
///
/// 这个独立函数让 SettingsPage struct（不持有 SettingsView 引用）可以直接进行本地化，
/// 避免需要依赖 SettingsView extension 上的 `localized(_:_:)` 实例方法。
/// 详见 ADR: docs/adrs/2026-04-22-settings-page-registry.md
func localized(_ chinese: String, _ english: String, in language: AppUILanguage) -> String {
    language == .english ? english : chinese
}

// MARK: - Localization bridge and language bindings

/// 核心 i18n 桥接：`localized(_:_:)` 函数、语言偏好读取和 Binding 封装。
/// P2 T7 会做完整 i18n 迁移，届时 `localized` 的实现可以直接在这里替换，
/// 不影响其他文件。
///
/// 2026-04-22 拆分自 Presentation.swift（见 ADR: docs/adrs/2026-04-22-presentation-split.md）
extension SettingsView {

    // MARK: Core localization primitive

    func localized(_ chinese: String, _ english: String) -> String {
        uiLanguage == .english ? english : chinese
    }

    // MARK: Language preference

    /// 壳层语言影响设置页、菜单栏弹层与状态文案。
    var uiLanguage: AppUILanguage {
        reminderPreferencesController.reminderPreferences.interfaceLanguage
    }

    /// 语言切换只改展示文本，不触发业务层重算。
    var interfaceLanguageBinding: Binding<AppUILanguage> {
        Binding(
            get: { uiLanguage },
            set: { language in
                Task {
                    await reminderPreferencesController.setInterfaceLanguage(language)
                }
            }
        )
    }

    // MARK: Countdown mode bindings

    /// 提醒页用两档模式表达当前时长来源：跟随音频，或固定手动秒数。
    var reminderCountdownModeBinding: Binding<ReminderCountdownMode> {
        Binding(
            get: {
                isCountdownFollowingSelectedSound ? .followSound : .manual
            },
            set: { mode in
                Task {
                    switch mode {
                    case .followSound:
                        await reminderPreferencesController.setCountdownOverrideSeconds(nil)
                    case .manual:
                        await reminderPreferencesController.setCountdownOverrideSeconds(effectiveCountdownSeconds)
                    }
                }
            }
        )
    }

    /// 手动模式下沿用现有 `countdownOverrideSeconds` 偏好，不改提醒引擎的调度规则。
    var manualCountdownSecondsBinding: Binding<Int> {
        Binding(
            get: {
                reminderPreferencesController.reminderPreferences.countdownOverrideSeconds ?? effectiveCountdownSeconds
            },
            set: { seconds in
                Task {
                    await reminderPreferencesController.setCountdownOverrideSeconds(seconds)
                }
            }
        )
    }
}
