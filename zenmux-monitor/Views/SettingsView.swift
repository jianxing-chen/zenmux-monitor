//
//  SettingsView.swift
//  zenmux-monitor
//
//  设置面板视图
//  功能：配置 API Key、刷新间隔等
//

import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @State private var apiKeyInput: String = ""
    @State private var refreshInterval: TimeInterval
    @State private var launchAtLogin: Bool
    @State private var showKeySaved = false
    @State private var deepseekKeyInput: String = ""
    @State private var showDeepseekKeySaved = false

    private let settings = SettingsManager.shared
    private let apiService = ZenmuxAPIService.shared

    init() {
        _apiKeyInput = State(initialValue: SettingsManager.shared.apiKey ?? "")
        _refreshInterval = State(initialValue: SettingsManager.shared.refreshInterval)
        _launchAtLogin = State(initialValue: SettingsManager.shared.launchAtLogin)
        _deepseekKeyInput = State(initialValue: SettingsManager.shared.deepseekAPIKey ?? "")
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                titleBar
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 6)

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        apiKeySection
                        deepseekKeySection
                        refreshSection
                        generalSection
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }

                Divider()
                    .overlay(SettingsPalette.border.opacity(0.7))

                bottomBar
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 400, idealHeight: 440)
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

                Text("API 配置与刷新策略")
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
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(
                    title: "Management API Key",
                    caption: "保存后立即拉取最新配额数据。",
                    systemImage: "key.fill"
                )

                HStack(spacing: 10) {
                    SecureField("请输入 Zenmux Management API Key", text: $apiKeyInput)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
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
                    .buttonStyle(SettingsProminentButtonStyle())
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

    // MARK: - DeepSeek API Key 区域

    private var deepseekKeySection: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(
                    title: "DeepSeek API Key",
                    caption: "用于下拉面板显示余额，菜单打开时拉取。",
                    systemImage: "creditcard.fill"
                )

                HStack(spacing: 10) {
                    SecureField("请输入 DeepSeek API Key（sk-...）", text: $deepseekKeyInput)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(SettingsPalette.border, lineWidth: 1)
                        )
                        .font(.callout)

                    Button {
                        let trimmed = deepseekKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        settings.deepseekAPIKey = trimmed.isEmpty ? nil : trimmed
                        UserDefaults.standard.removeObject(forKey: "deepseek_cached_balance")
                        UserDefaults.standard.removeObject(forKey: "deepseek_cached_updated")
                        showDeepseekKeySaved = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            showDeepseekKeySaved = false
                        }
                    } label: {
                        Label("保存", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(SettingsProminentButtonStyle())
                }

                HStack(spacing: 8) {
                    Link("前往 DeepSeek 控制台创建 Key", destination: URL(string: "https://platform.deepseek.com/api_keys")!)
                        .font(.subheadline)

                    Spacer()

                    if showDeepseekKeySaved {
                        statusBadge(title: "已保存", icon: "checkmark.circle.fill", tint: SettingsPalette.primaryText)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: showDeepseekKeySaved)
            }
        }
    }

    // MARK: - 刷新间隔

    private var refreshSection: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(
                    title: "自动刷新",
                    caption: "按设定间隔持续拉取最新配额数据。",
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
                    Text("应用将持续按选定间隔刷新，菜单中可随时暂停。")
                        .font(.subheadline)
                        .foregroundStyle(SettingsPalette.secondaryText)
                }
            }
        }
    }

    // MARK: - 通用设置

    private var generalSection: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 10) {
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
            .buttonStyle(SettingsProminentButtonStyle())
        }
    }

    private func persistAPIKey(forceFetch: Bool) {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let newValue = trimmed.isEmpty ? nil : trimmed
        let currentValue = settings.apiKey
        guard currentValue != newValue else { return }
        settings.apiKey = newValue
        apiService.settingsDidChange(forceFetch: forceFetch)
    }

    @ViewBuilder
    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
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
    static let actionFill = Color.primary.opacity(0.12)
    static let actionFillPressed = Color.primary.opacity(0.08)
    static let actionBorder = Color.primary.opacity(0.18)
    static let actionText = Color.primary
    static let tint = primaryText
}

private struct SettingsProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isEnabled ? SettingsPalette.actionText : SettingsPalette.secondaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(borderColor(isPressed: configuration.isPressed), lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.6)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        guard isEnabled else { return SettingsPalette.fill }
        return isPressed ? SettingsPalette.actionFillPressed : SettingsPalette.actionFill
    }

    private func borderColor(isPressed: Bool) -> Color {
        guard isEnabled else { return SettingsPalette.border }
        return SettingsPalette.actionBorder
    }
}

#Preview {
    SettingsView()
}
