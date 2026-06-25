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
        static let cachedSubscriptionData = "cached_subscription_data"
        static let cachedLastUpdated = "cached_last_updated"
        static let customApps = "custom_apps"
    }

    /// 刷新间隔下限（秒）。低于此值会触发忙循环与高频请求，写入时强制钳制。
    static let minRefreshInterval: TimeInterval = 10

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
        set {
            let previousValue = defaults.string(forKey: Keys.apiKey)
            defaults.set(newValue, forKey: Keys.apiKey)

            if previousValue != newValue {
                clearCachedSubscriptionSnapshot()
            }
        }
    }

    // MARK: - UserDefaults 操作

    var refreshInterval: TimeInterval {
        get { max(Self.minRefreshInterval, defaults.double(forKey: Keys.refreshInterval)) }
        set { defaults.set(max(Self.minRefreshInterval, newValue), forKey: Keys.refreshInterval) }
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
            guard let data = defaults.data(forKey: Keys.customApps),
                  let arr = try? JSONDecoder().decode([[String]].self, from: data) else {
                return []
            }
            return arr.compactMap { pair in
                pair.count == 2 ? (pair[0], pair[1]) : nil
            }
        }
        set {
            // 按 bundleID 去重，避免重复条目进入存储与监控集合。
            var seen = Set<String>()
            let deduped = newValue.filter { seen.insert($0.bundleID).inserted }
            let arr = deduped.map { [$0.bundleID, $0.name] }
            if let data = try? JSONEncoder().encode(arr) {
                defaults.set(data, forKey: Keys.customApps)
            }
        }
    }

    /// 始终刷新（忽略 App 检测）
    var alwaysRefresh: Bool {
        get { defaults.bool(forKey: Keys.alwaysRefresh) }
        set { defaults.set(newValue, forKey: Keys.alwaysRefresh) }
    }

    var cachedSubscriptionData: ZenmuxSubscriptionData? {
        get {
            guard let data = defaults.data(forKey: Keys.cachedSubscriptionData) else {
                return nil
            }
            return try? JSONDecoder().decode(ZenmuxSubscriptionData.self, from: data)
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: Keys.cachedSubscriptionData)
                return
            }

            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.cachedSubscriptionData)
            }
        }
    }

    var cachedLastUpdated: Date? {
        get { defaults.object(forKey: Keys.cachedLastUpdated) as? Date }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Keys.cachedLastUpdated)
            } else {
                defaults.removeObject(forKey: Keys.cachedLastUpdated)
            }
        }
    }

    func clearCachedSubscriptionSnapshot() {
        defaults.removeObject(forKey: Keys.cachedSubscriptionData)
        defaults.removeObject(forKey: Keys.cachedLastUpdated)
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
