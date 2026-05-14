//
//  SettingsView.swift
//  zenmux-monitor
//
//  设置面板视图
//  功能：配置 Management API Key、刷新间隔等
//

import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @State private var apiKeyInput: String = ""
    @State private var refreshInterval: TimeInterval
    @State private var launchAtLogin: Bool
    @State private var showKeySaved = false
    @State private var monitoredApps: Set<String>
    @State private var customApps: [(bundleID: String, name: String)]
    @State private var newBundleID: String = ""
    @State private var newAppName: String = ""
    @State private var alwaysRefresh: Bool

    private let settings = SettingsManager.shared
    private let apiService = ZenmuxAPIService.shared

    init() {
        _apiKeyInput = State(initialValue: SettingsManager.shared.apiKey ?? "")
        _refreshInterval = State(initialValue: SettingsManager.shared.refreshInterval)
        _launchAtLogin = State(initialValue: SettingsManager.shared.launchAtLogin)
        _monitoredApps = State(initialValue: SettingsManager.shared.monitoredAppIDs)
        _customApps = State(initialValue: SettingsManager.shared.customApps)
        _alwaysRefresh = State(initialValue: SettingsManager.shared.alwaysRefresh)
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    apiKeySection
                    refreshSection
                    monitoredAppsSection
                    customAppsSection
                    generalSection
                }
                .padding(20)
            }

            Divider()

            bottomBar
        }
        .frame(width: 420, height: 560)
    }

    // MARK: - 标题栏

    private var titleBar: some View {
        HStack {
            Image(systemName: "gearshape.fill")
                .foregroundStyle(.gray)
            Text("Zenmux 监控设置")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - API Key 区域

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Management API Key", systemImage: "key.fill")
                .font(.subheadline)
                .fontWeight(.medium)

            HStack(spacing: 8) {
                SecureField("请输入 Zenmux Management API Key", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)

                Button("保存") {
                    settings.apiKey = apiKeyInput
                    showKeySaved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showKeySaved = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            HStack {
                Text("在")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Link("Zenmux 控制台", destination: URL(string: "https://zenmux.ai/platform/management")!)
                    .font(.caption2)

                Text("创建 Management API Key")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if showKeySaved {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text("API Key 已保存")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                .transition(.opacity)
                .animation(.easeInOut, value: showKeySaved)
            }
        }
    }

    // MARK: - 刷新间隔

    private var refreshSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("自动刷新", systemImage: "arrow.triangle.2.circlepath")
                .font(.subheadline)
                .fontWeight(.medium)

            Picker("刷新间隔", selection: $refreshInterval) {
                Text("30 秒").tag(30.0)
                Text("1 分钟").tag(60.0)
                Text("5 分钟").tag(300.0)
                Text("10 分钟").tag(600.0)
                Text("30 分钟").tag(1800.0)
            }
            .pickerStyle(.segmented)
            .onChange(of: refreshInterval) { _, newValue in
                settings.refreshInterval = newValue
                ZenmuxAPIService.shared.startAutoRefresh(interval: newValue)
            }
        }
    }

    // MARK: - 监控 App 选择

    private var monitoredAppsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("仅在使用以下 App 时刷新用量", systemImage: "apps.iphone")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Toggle(isOn: $alwaysRefresh) {
                    Text("始终刷新")
                        .font(.caption)
                }
                .toggleStyle(.switch)
                .onChange(of: alwaysRefresh) { _, val in
                    settings.alwaysRefresh = val
                    if val {
                        apiService.startAutoRefresh(interval: settings.refreshInterval)
                    } else {
                        apiService.stopAutoRefresh()
                        ProcessMonitor.shared.refresh()
                    }
                }
            }

            if !alwaysRefresh {
                Text("勾选的 App 运行时自动刷新 API，全部关闭时暂停")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(SettingsManager.availableApps, id: \.bundleID) { app in
                    Toggle(isOn: binding(for: app.bundleID)) {
                        HStack(spacing: 4) {
                            if let icon = iconForBundleID(app.bundleID) {
                                Image(nsImage: icon)
                                    .resizable()
                                    .frame(width: 14, height: 14)
                            }
                            Text(app.name)
                                .font(.caption)
                        }
                        .frame(width: 160, alignment: .leading)
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    private func binding(for bundleID: String) -> Binding<Bool> {
        Binding(
            get: { monitoredApps.contains(bundleID) },
            set: { selected in
                if selected { monitoredApps.insert(bundleID) }
                else { monitoredApps.remove(bundleID) }
            }
        )
    }

    private func iconForBundleID(_ id: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    // MARK: - 自定义 App

    private var customAppsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("自定义 App", systemImage: "plus.square")
                .font(.subheadline)
                .fontWeight(.medium)

            // 添加新 App
            HStack(spacing: 4) {
                TextField("Bundle ID", text: $newBundleID)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                TextField("名称", text: $newAppName)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .frame(width: 100)
                Button("添加") {
                    addCustomApp()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(newBundleID.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            // 已添加的自定义 App 列表
            if !customApps.isEmpty {
                ForEach(customApps, id: \.bundleID) { app in
                    HStack {
                        Text(app.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(app.bundleID)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            customApps.removeAll { $0.bundleID == app.bundleID }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text("输入任意 App 的 Bundle Identifier 即可监控。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func addCustomApp() {
        let id = newBundleID.trimmingCharacters(in: .whitespaces)
        let name = newAppName.trimmingCharacters(in: .whitespaces).isEmpty
            ? id.components(separatedBy: ".").last ?? id
            : newAppName.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, !customApps.contains(where: { $0.bundleID == id }) else { return }
        customApps.append((id, name))
        newBundleID = ""
        newAppName = ""
    }

    // MARK: - 通用设置

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("通用", systemImage: "switch.2")
                .font(.subheadline)
                .fontWeight(.medium)

            Toggle(isOn: $launchAtLogin) {
                Text("登录时自动启动")
                    .font(.caption)
            }
            .toggleStyle(.switch)
            .onChange(of: launchAtLogin) { _, newValue in
                settings.launchAtLogin = newValue
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    print("自启动设置失败: \(error)")
                }
            }
        }
    }

    // MARK: - 底部栏

    private var bottomBar: some View {
        HStack {
            Spacer()
            Button("关闭") {
                if !apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty {
                    settings.apiKey = apiKeyInput
                }
                settings.monitoredAppIDs = monitoredApps
                settings.customApps = customApps
                ProcessMonitor.shared.refresh()
                ZenmuxAPIService.shared.startAutoRefresh(interval: settings.refreshInterval)
                NSApp.keyWindow?.close()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

#Preview {
    SettingsView()
}
