//
//  AppDelegate.swift
//  zenmux-monitor
//
//  macOS 菜单栏状态项管理器
//  使用原生 NSStatusItem + 自定义 NSView 绘制双进度条
//  替代 MenuBarExtra（其 label 宽度受系统硬限制）
//

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var statusView: StatusBarView!
    private var settingsWindow: NSWindow?
    private var isMenuOpen = false
    private var processObservers: [NSObjectProtocol] = []
    private let apiService = ZenmuxAPIService.shared
    private let settings = SettingsManager.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)  // 隐藏 Dock 图标
        setupStatusItem()
        observeProcessMonitor()
        observeAPIService()
        startMonitoringIfNeeded()
    }

    /// 启动即判断：始终刷新 or 有监控 App → 立刻拉数据；否则等通知
    private func startMonitoringIfNeeded() {
        let pm = ProcessMonitor.shared
        if SettingsManager.shared.alwaysRefresh || pm.isAnyMonitoredAppRunning {
            apiService.startAutoRefresh(interval: SettingsManager.shared.refreshInterval)
        }
    }

    // MARK: - 进程启停监听（App 运行时刷新，退出后停刷新）

    private func observeProcessMonitor() {
        let center = NotificationCenter.default

        let o1 = center.addObserver(forName: .monitoredAppDidLaunch, object: nil, queue: .main) {
            [weak self] _ in
            self?.apiService.startAutoRefresh(interval: self?.settings.refreshInterval ?? 60)
            Task { await self?.apiService.fetchSubscription(force: true) }
        }

        let o2 = center.addObserver(forName: .monitoredAppDidTerminate, object: nil, queue: .main) {
            [weak self] _ in
            self?.apiService.stopAutoRefresh()
            self?.statusView?.needsDisplay = true
        }
        processObservers = [o1, o2]
    }

    // MARK: - 数据观察（递归订阅，持续刷新进度条 + 暂停状态）

    @MainActor
    private func observeAPIService() {
        withObservationTracking { [weak self] in
            _ = self?.apiService.subscriptionData
            _ = self?.apiService.lastUpdated
            _ = self?.apiService.isPaused
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                statusView?.needsDisplay = true
                observeAPIService()
            }
        }
    }

    // MARK: - 状态栏项

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // 自定义绘制视图
        statusView = StatusBarView(frame: NSRect(x: 0, y: 0, width: 45, height: 22))
        statusView.apiService = apiService
        statusItem.button?.addSubview(statusView)
        statusItem.button?.frame = statusView.frame

        // 懒加载菜单：仅点击时才构建 SwiftUI 视图
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    // MARK: - 菜单构建（懒加载）

    private func buildMenuItems(into menu: NSMenu) {
        // --- 账号概览（SwiftUI 嵌入）---
        let headerItem = NSMenuItem()
        let headerView = MenuHeaderView(apiService: apiService)
        let hosting = NSHostingView(rootView: headerView.frame(width: 260))
        hosting.frame = NSRect(x: 0, y: 0, width: 260, height: 40)
        headerItem.view = hosting
        menu.addItem(headerItem)

        menu.addItem(.separator())

        // --- 配额详情（SwiftUI 嵌入）---
        if let data = apiService.subscriptionData {
            let quotaItem = NSMenuItem()
            let quotaView = MenuQuotaView(data: data)
            let quotaHosting = NSHostingView(rootView: quotaView.frame(width: 260))
            quotaHosting.frame = NSRect(x: 0, y: 0, width: 260, height: 145)
            quotaItem.view = quotaHosting
            menu.addItem(quotaItem)
        } else {
            let loadingItem = NSMenuItem(title: "加载中...", action: nil, keyEquivalent: "")
            loadingItem.isEnabled = false
            menu.addItem(loadingItem)
        }

        menu.addItem(.separator())

        // --- 操作按钮（设置 / 退出仍用 NSMenuItem；刷新已移入 SwiftUI 视图内）---
        let settingsItem = NSMenuItem(title: "设置", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 Zenmux Monitor", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            win.title = "Zenmux 监控设置"
            win.contentView = NSHostingView(rootView: SettingsView())
            win.center()
            win.isReleasedWhenClosed = false
            win.delegate = self
            settingsWindow = win
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        apiService.stopAutoRefresh()
        statusItem = nil
        NSApplication.shared.terminate(nil)
    }

    // MARK: - NSMenuDelegate（懒加载菜单）

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        if !menu.items.isEmpty { menu.removeAllItems() }
        buildMenuItems(into: menu)
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        // 关闭后释放菜单内的 NSHostingView（SwiftUI 占 ~10MB）
        menu.removeAllItems()
    }

    func windowWillClose(_ notification: Notification) {
        if let win = notification.object as? NSWindow, win == settingsWindow {
            win.contentView = nil  // 释放 NSHostingView + SwiftUI 视图
            settingsWindow = nil
        }
    }
}

// MARK: - 菜单栏自定义绘制视图

final class StatusBarView: NSView {
    weak var apiService: ZenmuxAPIService?

    override var intrinsicContentSize: NSSize {
        NSSize(width: 45, height: 22)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let data = apiService?.subscriptionData else {
            drawPlaceholder()
            return
        }

        // 暂停状态：无监控 App 运行，仅显示最后已知数据 + 暂停标记
        if apiService?.isPaused == true {
            drawPaused(data)
            return
        }

        let barH: CGFloat = 7
        let barW = bounds.width - 24
        let spacing: CGFloat = 2
        let topY = bounds.height - barH - 4
        let bottomY = topY - barH - spacing
        let corner: CGFloat = 2

        // 进度条
        drawBar(y: topY, width: barW, height: barH, pct: data.quota_5_hour.usage_percentage, radius: corner)
        drawBar(y: bottomY, width: barW, height: barH, pct: data.quota_7_day.usage_percentage, radius: corner)

        // 百分比文字（白色，对齐各自进度条）
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let textX = barW + 6
        drawPercent(text: percentStr(data.quota_5_hour.usage_percentage),
                    at: textX, barY: topY, barH: barH, attrs: textAttrs)
        drawPercent(text: percentStr(data.quota_7_day.usage_percentage),
                    at: textX, barY: bottomY, barH: barH, attrs: textAttrs)
    }

    /// 暂停状态：显示缩略进度条 + ⏸ 图标
    private func drawPaused(_ data: ZenmuxSubscriptionData) {
        let barH: CGFloat = 5
        let barW = bounds.width - 18
        let topY = bounds.height - barH - 5
        let bottomY = topY - barH - 2

        // 缩略进度条（灰色表示非实时）
        drawDimmedBar(y: topY, width: barW, height: barH, pct: data.quota_5_hour.usage_percentage)
        drawDimmedBar(y: bottomY, width: barW, height: barH, pct: data.quota_7_day.usage_percentage)

        // ⏸ 符号
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 7),
            .foregroundColor: NSColor.white.withAlphaComponent(0.4)
        ]
        "⏸".draw(at: NSPoint(x: barW + 4, y: bottomY - 1), withAttributes: attrs)
    }

    private func drawDimmedBar(y: CGFloat, width: CGFloat, height: CGFloat, pct: Double) {
        let barRect = NSRect(x: 4, y: y, width: width, height: height)
        let bg = NSBezierPath(roundedRect: barRect, xRadius: 2, yRadius: 2)
        NSColor.white.withAlphaComponent(0.08).setFill()
        bg.fill()

        let clamped = max(0, min(pct, 1))
        let fw = width * CGFloat(clamped)
        guard fw > 1 else { return }

        let fgRect = NSRect(x: 4, y: y, width: fw, height: height)
        NSColor.white.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: fgRect, xRadius: 2, yRadius: 2).fill()
    }

    private func percentStr(_ pct: Double) -> String {
        String(format: "%2d%%", Int(pct * 100))
    }

    private func drawPercent(text: String, at x: CGFloat, barY: CGFloat, barH: CGFloat,
                             attrs: [NSAttributedString.Key: Any]) {
        let size = text.size(withAttributes: attrs)
        let y = barY + (barH - size.height) / 2
        text.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
    }

    private func drawPlaceholder() {
        if let icon = NSApp.applicationIconImage {
            let size: CGFloat = 16
            let x = (bounds.width - size) / 2
            let y = (bounds.height - size) / 2
            icon.draw(in: NSRect(x: x, y: y, width: size, height: size),
                      from: .zero, operation: .sourceOver, fraction: 0.85)
        }
    }

    private func drawBar(y: CGFloat, width: CGFloat, height: CGFloat, pct: Double, radius: CGFloat) {
        let barRect = NSRect(x: 4, y: y, width: width, height: height)

        // 背景
        let bg = NSBezierPath(roundedRect: barRect, xRadius: radius, yRadius: radius)
        NSColor.white.withAlphaComponent(0.15).setFill()
        bg.fill()

        let clamped = max(0, min(pct, 1))
        let fw = width * CGFloat(clamped)
        guard fw > 1 else { return }

        let fgRect = NSRect(x: 4, y: y, width: fw, height: height)

        let color: NSColor
        if pct > 0.8 { color = .systemRed }
        else if pct > 0.5 { color = .systemOrange }
        else { color = .systemBlue }

        if fw < radius * 2 {
            color.setFill()
            NSBezierPath(rect: fgRect).fill()
        } else {
            color.setFill()
            NSBezierPath(roundedRect: fgRect, xRadius: radius, yRadius: radius).fill()
        }
    }
}

// MARK: - 菜单 Header 视图

struct MenuHeaderView: View {
    let apiService: ZenmuxAPIService

    var body: some View {
        HStack {
            if let data = apiService.subscriptionData {
                let status = ZenmuxAccountStatus.from(data.account_status)
                Image(systemName: status.systemImage)
                    .foregroundStyle(statusColor(status))
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Zenmux \(data.plan.tier.capitalized)")
                        .font(.headline)
                    HStack(spacing: 4) {
                        Circle().fill(statusColor(status)).frame(width: 5, height: 5)
                        Text(status.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("到期 \(formatDate(data.plan.expires_at))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        if apiService.isPaused {
                            Text("⏸ 暂停")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            } else {
                Image(systemName: "circle.dotted")
                VStack(alignment: .leading, spacing: 2) {
                    Text("未连接")
                        .font(.headline)
                    if let err = apiService.lastError {
                        Text(err)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private static let dateFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MM/dd"; return f }()
    private static let isoFmt: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()

    private func formatDate(_ iso: String) -> String {
        guard let date = Self.isoFmt.date(from: iso) else { return String(iso.prefix(10)) }
        return Self.dateFmt.string(from: date)
    }

    private func statusColor(_ s: ZenmuxAccountStatus) -> Color {
        switch s {
        case .healthy: .green; case .monitored: .yellow
        case .abusive: .orange; case .suspended, .banned: .red
        case .unknown: .gray
        }
    }
}

// MARK: - 菜单配额视图

struct MenuQuotaView: View {
    let data: ZenmuxSubscriptionData

    var body: some View {
        VStack(spacing: 4) {
            QuotaRow(
                label: "5 小时用量", icon: "clock",
                pct: data.quota_5_hour.usage_percentage,
                used: data.quota_5_hour.used_flows,
                maxFlows: data.quota_5_hour.max_flows,
                usedUSD: data.quota_5_hour.used_value_usd,
                maxUSD: data.quota_5_hour.max_value_usd
            )
            QuotaRow(
                label: "7 天用量", icon: "calendar",
                pct: data.quota_7_day.usage_percentage,
                used: data.quota_7_day.used_flows,
                maxFlows: data.quota_7_day.max_flows,
                usedUSD: data.quota_7_day.used_value_usd,
                maxUSD: data.quota_7_day.max_value_usd
            )

            Divider()

            // 月度上限
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.caption2).foregroundStyle(.purple)
                Text("当月上限")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(formatNum(data.quota_monthly.max_flows)) flows")
                    .font(.caption).fontWeight(.medium)
                Text("($\(formatNum(data.quota_monthly.max_value_usd)))")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            // 汇率信息
            HStack {
                Image(systemName: "dollarsign.circle")
                    .font(.caption2).foregroundStyle(.green)
                Text("汇率")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("$\(String(format: "%.4f", data.effective_usd_per_flow))/flow")
                    .font(.caption).foregroundStyle(.primary)
            }

            if let updated = ZenmuxAPIService.shared.lastUpdated {
                let api = ZenmuxAPIService.shared
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text("更新于 \(relativeTime(updated))")
                        .font(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                    Button {
                        if api.isPaused {
                            api.startAutoRefresh(interval: SettingsManager.shared.refreshInterval)
                            Task { await api.fetchSubscription(force: true) }
                        } else {
                            api.stopAutoRefresh()
                        }
                    } label: {
                        Image(systemName: api.isPaused ? "play.circle" : "pause.circle")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(api.isPaused ? .green : .orange)
                    .frame(width: 20, height: 20)
                    Button {
                        Task { await api.fetchSubscription(force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .frame(width: 20, height: 20)
                }
                .frame(height: 22)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func formatNum(_ v: Double) -> String {
        v >= 10000 ? String(format: "%.2fk", v / 1000)
                   : String(format: "%.2f", v)
    }

    private func relativeTime(_ date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 60 { return "\(s)秒前" }
        if s < 3600 { return "\(s / 60)分前" }
        return "\(s / 3600)时前"
    }
}

struct QuotaRow: View {
    let label: String; let icon: String
    let pct: Double; let used: Double; let maxFlows: Double
    let usedUSD: Double; let maxUSD: Double

    var body: some View {
        VStack(spacing: 2) {
            // 标题 + 百分比
            HStack {
                Image(systemName: icon).font(.caption).foregroundStyle(.blue)
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.2f%%", pct * 100))
                    .font(.caption).fontWeight(.medium).monospacedDigit()
                    .foregroundStyle(pct > 0.8 ? .red : pct > 0.5 ? .orange : .primary)
            }

            // 进度条
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(.primary.opacity(0.1)).frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(pct > 0.8 ? .red : pct > 0.5 ? .orange : .blue)
                        .frame(width: max(0, geo.size.width * pct), height: 4)
                }
            }
            .frame(height: 4)

            // 用量数值（精确到 1 位小数）
            HStack {
                Text("已用 \(String(format: "%.2f", used))/\(String(format: "%.2f", maxFlows)) flows")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("$\(String(format: "%.2f", usedUSD)) / $\(String(format: "%.2f", maxUSD))")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}
