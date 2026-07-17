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
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        apiKeySection
                        deepseekKeySection
                        refreshSection
                        generalSection
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                }

                Divider()

                bottomBar
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
        }
        .frame(minWidth: 460, idealWidth: 480, minHeight: 340, idealHeight: 360)
    }

    // MARK: - API Key 区域

    private var apiKeySection: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    if let appIcon = NSApp.applicationIconImage {
                        Image(nsImage: appIcon)
                            .resizable()
                            .frame(width: 32, height: 32)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Zenmux Platform API")
                            .font(.headline)
                            .foregroundStyle(SettingsPalette.primaryText)
                        Text("保存后立即拉取最新配额数据。")
                            .font(.subheadline)
                            .foregroundStyle(SettingsPalette.secondaryText)
                    }
                }

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

                    if showKeySaved {
                        statusBadge(title: "已保存", icon: "checkmark.circle.fill", tint: .green)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: showKeySaved)

                HStack {
                    Link("前往 Zenmux 控制台创建 Key", destination: URL(string: "https://zenmux.ai/platform/management")!)
                        .font(.subheadline)
                    Spacer()
                    statusBadge(title: settings.apiKey?.isEmpty == false ? "已连接" : "未配置", icon: "bolt.fill", tint: settings.apiKey?.isEmpty == false ? .green : .secondary)
                }
            }
        }
    }

    // MARK: - DeepSeek API Key 区域

    private var deepseekKeySection: some View {
        sectionCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image("DeepSeekLogo")
                        .resizable()
                        .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DeepSeek API")
                            .font(.headline)
                            .foregroundStyle(SettingsPalette.primaryText)
                        Text("用于下拉面板显示余额，菜单打开时拉取。")
                            .font(.subheadline)
                            .foregroundStyle(SettingsPalette.secondaryText)
                    }
                }

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

                    if showDeepseekKeySaved {
                        statusBadge(title: "已保存", icon: "checkmark.circle.fill", tint: .green)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: showDeepseekKeySaved)

                HStack {
                    Link("前往 DeepSeek 控制台创建 Key", destination: URL(string: "https://platform.deepseek.com/api_keys")!)
                        .font(.subheadline)
                    Spacer()
                    statusBadge(title: settings.deepseekAPIKey?.isEmpty == false ? "已配置" : "未配置", icon: "bolt.fill", tint: settings.deepseekAPIKey?.isEmpty == false ? .green : .secondary)
                }
            }
        }
    }

    // MARK: - 刷新间隔

    private var refreshSection: some View {
        sectionCard {
            HStack {
                Text("自动刷新间隔")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SettingsPalette.primaryText)
                Spacer()
                Picker("", selection: $refreshInterval) {
                    Text("30s").tag(30.0)
                    Text("1m").tag(60.0)
                    Text("2m").tag(120.0)
                    Text("5m").tag(300.0)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                .onChange(of: refreshInterval) { _, newValue in
                    settings.refreshInterval = newValue
                    apiService.settingsDidChange(forceFetch: true)
                }
            }
        }
    }

    // MARK: - 通用设置

    private var generalSection: some View {
        sectionCard {
            HStack {
                Text("登录时自动启动")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SettingsPalette.primaryText)
                Spacer()
                Toggle("", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .labelsHidden()
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
            .foregroundStyle(isEnabled ? .white : .secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(minHeight: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isEnabled
                        ? (configuration.isPressed ? Color.primary.opacity(0.65) : Color.primary.opacity(0.78))
                        : Color.primary.opacity(0.12))
            )
            .opacity(isEnabled ? 1 : 0.5)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    SettingsView()
}
