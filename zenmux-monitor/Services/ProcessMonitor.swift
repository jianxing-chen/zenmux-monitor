//
//  ProcessMonitor.swift
//  zenmux-monitor
//
//  进程监控服务
//  GUI App：NSWorkspace 通知实时检测 Bundle ID
//

import AppKit

extension Notification.Name {
    static let monitoredAppDidLaunch  = Notification.Name("monitoredAppDidLaunch")
    static let monitoredAppDidTerminate = Notification.Name("monitoredAppDidTerminate")
}

final class ProcessMonitor {
    static let shared = ProcessMonitor()

    /// GUI App Bundle ID 列表
    private var monitoredBundleIDs: Set<String> = []
    private var runningMonitoredApps = Set<String>()
    private var workspaceObservers: [NSObjectProtocol] = []
    private var isCleaningUp = false

    private(set) var isAnyMonitoredAppRunning = false {
        didSet {
            guard !isCleaningUp, isAnyMonitoredAppRunning != oldValue else { return }
            let name: Notification.Name = isAnyMonitoredAppRunning
                ? .monitoredAppDidLaunch : .monitoredAppDidTerminate
            NotificationCenter.default.post(name: name, object: nil)
        }
    }

    private init() {
        observeAppLifecycle()
        refresh()
    }

    /// 重新加载设置 + 扫描运行状态
    func refresh() {
        guard !isCleaningUp else { return }
        if SettingsManager.shared.alwaysRefresh {
            isAnyMonitoredAppRunning = true
            return
        }
        let predefined = SettingsManager.shared.monitoredAppIDs
        let custom = Set(SettingsManager.shared.customApps.map { $0.bundleID })
        monitoredBundleIDs = predefined.union(custom)
        refreshRunningState()
    }

    // MARK: - 系统通知监听（GUI App）

    private func observeAppLifecycle() {
        let nCenter = NSWorkspace.shared.notificationCenter

        let launchObserver = nCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                                 object: nil, queue: .main) { [weak self] notif in
            self?.handleAppLaunch(notif)
        }

        let terminateObserver = nCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                                    object: nil, queue: .main) { [weak self] notif in
            self?.handleAppTerminate(notif)
        }

        workspaceObservers = [launchObserver, terminateObserver]
    }

    func cleanup() {
        guard !isCleaningUp else { return }
        isCleaningUp = true

        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { center.removeObserver($0) }
        workspaceObservers.removeAll()
        runningMonitoredApps.removeAll()
        monitoredBundleIDs.removeAll()
        isAnyMonitoredAppRunning = false
    }

    private func handleAppLaunch(_ notif: Notification) {
        guard !isCleaningUp,
              let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier,
              monitoredBundleIDs.contains(bundleID) else { return }
        runningMonitoredApps.insert(bundleID)
        isAnyMonitoredAppRunning = true
    }

    private func handleAppTerminate(_ notif: Notification) {
        guard !isCleaningUp,
              let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier,
              monitoredBundleIDs.contains(bundleID) else { return }
        runningMonitoredApps.remove(bundleID)
        isAnyMonitoredAppRunning = !runningMonitoredApps.isEmpty
    }

    private func refreshRunningState() {
        let running = Set(
            NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier }
        )
        runningMonitoredApps = monitoredBundleIDs.intersection(running)
        isAnyMonitoredAppRunning = !runningMonitoredApps.isEmpty
    }
}
