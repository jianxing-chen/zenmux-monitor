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
    private let appColumns = [
        GridItem(.flexible(minimum: 180), spacing: 12),
        GridItem(.flexible(minimum: 180), spacing: 12)
    ]

    init() {
        _apiKeyInput = State(initialValue: SettingsManager.shared.apiKey ?? "")
        _refreshInterval = State(initialValue: SettingsManager.shared.refreshInterval)
        _launchAtLogin = State(initialValue: SettingsManager.shared.launchAtLogin)
        _monitoredApps = State(initialValue: SettingsManager.shared.monitoredAppIDs)
        _customApps = State(initialValue: SettingsManager.shared.customApps)
        _alwaysRefresh = State(initialValue: SettingsManager.shared.alwaysRefresh)
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                titleBar
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        apiKeySection
                        refreshSection
                        monitoredAppsSection
                        customAppsSection
                        generalSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                }

                Divider()
                    .overlay(SettingsPalette.border.opacity(0.7))

                bottomBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
        .frame(minWidth: 540, idealWidth: 580, minHeight: 640, idealHeight: 700)
    }

    // MARK: - 标题栏

    private var titleBar: some View {
        HStack(spacing: 10) {
            Group {
                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .interpolation(.high)
                } else {
                    Image(systemName: "waveform.path.ecg.rectangle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SettingsPalette.primaryText)
                }
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text("Zenmux Monitor")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SettingsPalette.primaryText)

                Text("API 刷新策略与监控应用管理")
                    .font(.system(size: 11))
                    .foregroundStyle(SettingsPalette.secondaryText)
            }

            Spacer()

            statusBadge(title: settings.apiKey?.isEmpty == false ? "已连接" : "未配置", icon: "bolt.fill")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(SettingsPalette.border, lineWidth: 1)
        )
    }

    // MARK: - API Key 区域

    private var apiKeySection: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(
                    title: "Management API Key",
                    caption: "保存后立即拉取最新配额数据。",
                    systemImage: "key.fill"
                )

                HStack(spacing: 10) {
                    SecureField("请输入 Zenmux Management API Key", text: $apiKeyInput)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(SettingsPalette.border, lineWidth: 1)
                        )
                        .font(.callout)

                    Button {
                        persistAPIKey(forceFetch: true)
                        showKeySaved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            showKeySaved = false
                        }
                    } label: {
                        Label("保存", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.primary)
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                HStack(spacing: 8) {
                    Link("前往 Zenmux 控制台创建 Key", destination: URL(string: "https://zenmux.ai/platform/management")!)
                        .font(.subheadline)

                    Spacer()

                    if showKeySaved {
                        statusBadge(title: "已保存", icon: "checkmark.circle.fill", tint: SettingsPalette.primaryText)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: showKeySaved)
            }
        }
    }

    // MARK: - 刷新间隔

    private var refreshSection: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(
                    title: "自动刷新",
                    caption: "用尽量少的网络请求维持实时感知。",
                    systemImage: "arrow.triangle.2.circlepath"
                )

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
                    apiService.settingsDidChange(forceFetch: true)
                }

                HStack(spacing: 8) {
                    Image(systemName: "clock.badge.checkmark.fill")
                        .foregroundStyle(SettingsPalette.primaryText)
                    Text(refreshSummaryText)
                        .font(.subheadline)
                        .foregroundStyle(SettingsPalette.secondaryText)
                }
            }
        }
    }

    // MARK: - 监控 App 选择

    private var monitoredAppsSection: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    sectionHeader(
                        title: "触发刷新应用",
                        caption: alwaysRefresh ? "已忽略应用检测，按设定间隔持续刷新。" : "仅在以下应用活跃时发起自动刷新。",
                        systemImage: "app.badge"
                    )

                    Spacer()

                    Toggle("始终刷新", isOn: $alwaysRefresh)
                        .toggleStyle(.switch)
                        .font(.subheadline.weight(.medium))
                        .onChange(of: alwaysRefresh) { _, val in
                            settings.alwaysRefresh = val
                            apiService.settingsDidChange(forceFetch: true)
                        }
                }

                if !alwaysRefresh {
                    LazyVGrid(columns: appColumns, alignment: .leading, spacing: 12) {
                        ForEach(SettingsManager.availableApps, id: \.bundleID) { app in
                            appToggleCard(app)
                        }
                    }
                } else {
                    statusRow(
                        title: "当前模式",
                        detail: "所有时段都刷新，不再依赖 IDE 或 AI 工具是否开启。",
                        systemImage: "bolt.circle.fill",
                        tint: SettingsPalette.primaryText
                    )
                }
            }
        }
    }

    private func appToggleCard(_ app: (bundleID: String, name: String)) -> some View {
        let isSelected = monitoredApps.contains(app.bundleID)

        return Toggle(isOn: binding(for: app.bundleID)) {
            HStack(spacing: 10) {
                Group {
                    if let icon = iconForBundleID(app.bundleID) {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                    } else {
                        Image(systemName: "app.fill")
                            .resizable()
                            .scaledToFit()
                            .padding(4)
                            .foregroundStyle(SettingsPalette.primaryText)
                    }
                }
                .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(SettingsPalette.primaryText)
                        .lineLimit(1)
                    Text(app.bundleID)
                        .font(.caption)
                        .foregroundStyle(SettingsPalette.secondaryText)
                        .lineLimit(1)
                }
            }
        }
        .toggleStyle(.checkbox)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? SettingsPalette.fillSelected : SettingsPalette.fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? SettingsPalette.borderStrong : SettingsPalette.border, lineWidth: 1)
        )
    }

    private func binding(for bundleID: String) -> Binding<Bool> {
        Binding(
            get: { monitoredApps.contains(bundleID) },
            set: { selected in
                if selected { monitoredApps.insert(bundleID) }
                else { monitoredApps.remove(bundleID) }
                settings.monitoredAppIDs = monitoredApps
                apiService.settingsDidChange(forceFetch: true)
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
        sectionCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(
                    title: "自定义 App",
                    caption: "输入 Bundle Identifier，把任意工具纳入刷新触发列表。",
                    systemImage: "plus.square.on.square"
                )

                HStack(spacing: 10) {
                    TextField("Bundle ID", text: $newBundleID)
                        .textFieldStyle(.roundedBorder)
                        .font(.callout)

                    TextField("名称（可选）", text: $newAppName)
                        .textFieldStyle(.roundedBorder)
                        .font(.callout)
                        .frame(width: 130)

                    Button {
                        addCustomApp()
                    } label: {
                        Label("添加", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .tint(.primary)
                    .disabled(newBundleID.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if customApps.isEmpty {
                    statusRow(
                        title: "暂无自定义应用",
                        detail: "例如 `com.apple.Terminal` 或其他 AI / IDE 工具。",
                        systemImage: "sparkles.rectangle.stack",
                        tint: SettingsPalette.secondaryText
                    )
                } else {
                    VStack(spacing: 10) {
                        ForEach(customApps, id: \.bundleID) { app in
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(SettingsPalette.fill)
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "app.connected.to.app.below.fill")
                                        .foregroundStyle(SettingsPalette.primaryText)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(SettingsPalette.primaryText)
                                    Text(app.bundleID)
                                        .font(.caption)
                                        .foregroundStyle(SettingsPalette.secondaryText)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Button {
                                    customApps.removeAll { $0.bundleID == app.bundleID }
                                    persistCustomApps(forceFetch: true)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(SettingsPalette.secondaryText)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("移除 \(app.name)")
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.primary.opacity(0.035))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(SettingsPalette.border, lineWidth: 1)
                            )
                        }
                    }
                }
            }
        }
    }

    private func addCustomApp() {
        let id = newBundleID.trimmingCharacters(in: .whitespaces)
        let name = newAppName.trimmingCharacters(in: .whitespaces).isEmpty
            ? id.components(separatedBy: ".").last ?? id
            : newAppName.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, !customApps.contains(where: { $0.bundleID == id }) else { return }
        customApps.append((id, name))
        persistCustomApps(forceFetch: true)
        newBundleID = ""
        newAppName = ""
    }

    private func persistCustomApps(forceFetch: Bool) {
        settings.customApps = customApps
        apiService.settingsDidChange(forceFetch: forceFetch)
    }

    private func persistAPIKey(forceFetch: Bool) {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let newValue = trimmed.isEmpty ? nil : trimmed
        let currentValue = settings.apiKey
        guard currentValue != newValue else { return }
        settings.apiKey = newValue
        apiService.settingsDidChange(forceFetch: forceFetch)
    }

    // MARK: - 通用设置

    private var generalSection: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(
                    title: "通用",
                    caption: "保持低打扰，仅在你需要时常驻可见。",
                    systemImage: "switch.2"
                )

                Toggle(isOn: $launchAtLogin) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("登录时自动启动")
                            .font(.subheadline.weight(.medium))
                        Text("开机后自动驻留菜单栏，免去手动打开。")
                            .font(.caption)
                            .foregroundStyle(SettingsPalette.secondaryText)
                    }
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
    }

    // MARK: - 底部栏

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Text("设置会自动保存，本窗口可随时关闭。")
                .font(.subheadline)
                .foregroundStyle(SettingsPalette.secondaryText)

            Spacer()

            Button("完成") {
                persistAPIKey(forceFetch: true)
                NSApp.keyWindow?.close()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.primary)
        }
    }

    private var refreshSummaryText: String {
        if alwaysRefresh {
            return "当前为始终刷新模式，会按选定时间间隔持续更新。"
        }

        let appCount = monitoredApps.count
        if appCount == 0 {
            return "尚未勾选触发应用，自动刷新将在手动刷新时进行。"
        }
        return "已选择 \(appCount) 个触发应用，仅在它们运行时自动刷新。"
    }

    @ViewBuilder
    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(SettingsPalette.border, lineWidth: 1)
            )
    }

    private func sectionHeader(title: String, caption: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SettingsPalette.fill)
                    .frame(width: 32, height: 32)
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SettingsPalette.primaryText)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(SettingsPalette.primaryText)
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(SettingsPalette.secondaryText)
            }
        }
    }

    private func statusRow(title: String, detail: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SettingsPalette.primaryText)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(SettingsPalette.secondaryText)
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(SettingsPalette.fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(SettingsPalette.border, lineWidth: 1)
        )
    }

    private func statusBadge(title: String, icon: String, tint: Color = SettingsPalette.tint) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
            Text(title)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(SettingsPalette.fill)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(SettingsPalette.border, lineWidth: 1)
        )
    }
}

private enum SettingsPalette {
    static let primaryText = Color(nsColor: .labelColor)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static let fill = Color.white.opacity(0.08)
    static let fillSelected = Color.white.opacity(0.14)
    static let border = Color.white.opacity(0.16)
    static let borderStrong = Color.white.opacity(0.28)
    static let tint = primaryText
}

#Preview {
    SettingsView()
}
