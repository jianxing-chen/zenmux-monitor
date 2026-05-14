//
//  SettingsManager.swift
//  zenmux-monitor
//
//  应用设置管理器
//  所有配置均使用 UserDefaults 持久化
//

import Foundation

final class SettingsManager {
    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let apiKey = "api_key"
        static let refreshInterval = "refresh_interval"
        static let launchAtLogin = "launch_at_login"
        static let monitoredAppIDs = "monitored_app_ids"
        static let alwaysRefresh = "always_refresh"
    }

    private init() {
        defaults.register(defaults: [
            Keys.refreshInterval: 60.0,
            Keys.monitoredAppIDs: [
                "com.microsoft.VSCode",
                "com.todesktop.230313mzl4w4u92",
                "com.cursor.Cursor",
            ],
        ])
    }

    // MARK: - API Key

    var apiKey: String? {
        get { defaults.string(forKey: Keys.apiKey) }
        set { defaults.set(newValue, forKey: Keys.apiKey) }
    }

    // MARK: - UserDefaults 操作

    var refreshInterval: TimeInterval {
        get { defaults.double(forKey: Keys.refreshInterval) }
        set { defaults.set(newValue, forKey: Keys.refreshInterval) }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Keys.launchAtLogin) }
        set { defaults.set(newValue, forKey: Keys.launchAtLogin) }
    }

    /// 用户选中的监控 App Bundle ID 集合
    var monitoredAppIDs: Set<String> {
        get {
            Set(defaults.stringArray(forKey: Keys.monitoredAppIDs) ?? [])
        }
        set {
            defaults.set(Array(newValue), forKey: Keys.monitoredAppIDs)
        }
    }

    /// 白名单之外的额外 App（bundleID + 显示名）
    var customApps: [(bundleID: String, name: String)] {
        get {
            guard let data = defaults.data(forKey: "custom_apps"),
                  let arr = try? JSONDecoder().decode([[String]].self, from: data) else {
                return []
            }
            return arr.compactMap { pair in
                pair.count == 2 ? (pair[0], pair[1]) : nil
            }
        }
        set {
            let arr = newValue.map { [$0.bundleID, $0.name] }
            if let data = try? JSONEncoder().encode(arr) {
                defaults.set(data, forKey: "custom_apps")
            }
        }
    }

    /// 始终刷新（忽略 App 检测）
    var alwaysRefresh: Bool {
        get { defaults.bool(forKey: Keys.alwaysRefresh) }
        set { defaults.set(newValue, forKey: Keys.alwaysRefresh) }
    }

    /// 菜单栏百分比文字颜色：true = 黑色，false = 白色（默认）
    var useBlackText: Bool {
        get { defaults.bool(forKey: "use_black_text") }
        set { defaults.set(newValue, forKey: "use_black_text") }
    }

    /// 所有可供选择的监控 App（不可变列表）
    static let availableApps: [(bundleID: String, name: String)] = [
        ("com.microsoft.VSCode",            "VS Code"),
        ("com.microsoft.VSCodeInsiders",    "VS Code Insiders"),
        ("com.todesktop.230313mzl4w4u92",  "Cursor"),
        ("com.cursor.Cursor",               "Cursor (alt)"),
        ("dev.windsurf.Windsurf",           "Windsurf"),
        ("com.anthropic.claude",            "Claude Desktop"),
        ("com.jetbrains.intellij",          "IntelliJ IDEA"),
        ("com.jetbrains.pycharm",           "PyCharm"),
    ]
}
