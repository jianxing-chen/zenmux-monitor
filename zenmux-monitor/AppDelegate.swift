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
    private var settingsWindow: NSWindow?
    private var processObservers: [NSObjectProtocol] = []
    private var appearanceObservers: [NSObjectProtocol] = []
    private let apiService = ZenmuxAPIService.shared
    private let statusView = StatusBarView(frame: NSRect(x: 0, y: 0, width: 42, height: 22))

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        _ = ProcessMonitor.shared
        observeProcessMonitor()
        observeAPIService()
        observeAppearanceChanges()
        apiService.refreshPolicyDidChange(forceFetch: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        let defaultCenter = NotificationCenter.default
        processObservers.forEach { defaultCenter.removeObserver($0) }
        processObservers.removeAll()

        let distributedCenter = DistributedNotificationCenter.default()
        appearanceObservers.forEach { distributedCenter.removeObserver($0) }
        appearanceObservers.removeAll()
    }

    // MARK: - 进程启停监听（App 运行时刷新，退出后停刷新）

    private func observeProcessMonitor() {
        let center = NotificationCenter.default

        let o1 = center.addObserver(forName: .monitoredAppDidLaunch, object: nil, queue: .main) {
            [weak self] _ in
            Task { @MainActor [weak self] in
                self?.apiService.refreshPolicyDidChange(forceFetch: true)
            }
        }

        let o2 = center.addObserver(forName: .monitoredAppDidTerminate, object: nil, queue: .main) {
            [weak self] _ in
            Task { @MainActor [weak self] in
                self?.apiService.refreshPolicyDidChange()
            }
        }
        processObservers = [o1, o2]
    }

    // MARK: - 数据观察（状态变化时刷新进度条）

    @MainActor
    private func observeAPIService() {
        apiService.onStateChange = { [weak self] in
            self?.updateStatusItemImage()
        }
        updateStatusItemImage()
    }

    // MARK: - 状态栏项

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.length = statusView.intrinsicContentSize.width

        statusView.apiService = apiService

        if let button = statusItem.button {
            button.title = ""
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
        }
        updateStatusItemImage()

        // 懒加载菜单：仅点击时才构建 SwiftUI 视图
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private func observeAppearanceChanges() {
        let observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateStatusItemImage()
            }
        }
        appearanceObservers = [observer]
    }

    @MainActor
    private func updateStatusItemImage() {
        guard let button = statusItem.button else { return }
        statusView.appearance = resolvedStatusBarAppearance
        button.image = statusView.renderedImage()
        button.needsDisplay = true
    }

    private var resolvedStatusBarAppearance: NSAppearance {
        NSApp.effectiveAppearance
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
            quotaHosting.frame = NSRect(x: 0, y: 0, width: 260, height: 165)
            quotaItem.view = quotaHosting
            menu.addItem(quotaItem)
        } else {
            let loadingItem = NSMenuItem(title: "加载中...", action: nil, keyEquivalent: "")
            loadingItem.isEnabled = false
            menu.addItem(loadingItem)
        }

        menu.addItem(.separator())

        // --- 文字颜色切换 ---
        let isBlack = SettingsManager.shared.useBlackText
        let colorItem = NSMenuItem(
            title: isBlack ? "百分比颜色：◉ 黑色" : "百分比颜色：◉ 白色",
            action: #selector(toggleTextColor),
            keyEquivalent: ""
        )
        colorItem.target = self
        menu.addItem(colorItem)

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

    @objc private func toggleTextColor() {
        let settings = SettingsManager.shared
        settings.useBlackText.toggle()
        updateStatusItemImage()
    }

    // MARK: - NSMenuDelegate（懒加载菜单）

    func menuWillOpen(_ menu: NSMenu) {
        if !menu.items.isEmpty { menu.removeAllItems() }
        buildMenuItems(into: menu)
    }

    func menuDidClose(_ menu: NSMenu) {
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

    private static let percentFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
    private static let pausedFont = NSFont.systemFont(ofSize: 7)

    private struct Palette {
        let barBackground: NSColor
        let pausedBackground: NSColor
        let pausedFill: NSColor
        let lowUsage: NSColor
        let midUsage: NSColor
        let highUsage: NSColor
        let primaryText: NSColor
        let secondaryText: NSColor
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 42, height: 22)
    }

    func renderedImage() -> NSImage {
        let bounds = NSRect(origin: .zero, size: intrinsicContentSize)
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else {
            return NSImage(size: intrinsicContentSize)
        }

        cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: intrinsicContentSize)
        image.addRepresentation(rep)
        image.isTemplate = false
        return image
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let data = apiService?.subscriptionData else {
            drawPlaceholder()
            return
        }

        if apiService?.isPaused == true {
            drawPaused(data)
            return
        }

        let palette = currentPalette
        let layout = normalLayoutMetrics

        let barH: CGFloat = 7
        let spacing: CGFloat = 2
        let topY = bounds.height - barH - 4
        let bottomY = topY - barH - spacing
        let corner: CGFloat = 2

        // 进度条
        drawBar(x: layout.barX, y: topY, width: layout.barWidth, height: barH,
                pct: data.quota_5_hour.usage_percentage, radius: corner, palette: palette)
        drawBar(x: layout.barX, y: bottomY, width: layout.barWidth, height: barH,
                pct: data.quota_7_day.usage_percentage, radius: corner, palette: palette)

        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: Self.percentFont,
            .foregroundColor: palette.primaryText
        ]
        drawPercent(text: percentStr(data.quota_5_hour.usage_percentage),
                at: layout.textX, barY: topY, barH: barH, attrs: textAttrs)
        drawPercent(text: percentStr(data.quota_7_day.usage_percentage),
                at: layout.textX, barY: bottomY, barH: barH, attrs: textAttrs)
    }

    /// 暂停状态：显示缩略进度条 + ⏸ 图标
    private func drawPaused(_ data: ZenmuxSubscriptionData) {
        let palette = currentPalette
        let layout = pausedLayoutMetrics
        let barH: CGFloat = 5
        let topY = bounds.height - barH - 5
        let bottomY = topY - barH - 2

        // 缩略进度条（灰色表示非实时）
        drawDimmedBar(x: layout.barX, y: topY, width: layout.barWidth, height: barH,
                      pct: data.quota_5_hour.usage_percentage, palette: palette)
        drawDimmedBar(x: layout.barX, y: bottomY, width: layout.barWidth, height: barH,
                      pct: data.quota_7_day.usage_percentage, palette: palette)

        // ⏸ 符号
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Self.pausedFont,
            .foregroundColor: palette.secondaryText
        ]
        "⏸".draw(at: NSPoint(x: layout.textX, y: bottomY - 1), withAttributes: attrs)
    }

    private func drawDimmedBar(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat,
                               pct: Double, palette: Palette) {
        let barRect = NSRect(x: x, y: y, width: width, height: height)
        let bg = NSBezierPath(roundedRect: barRect, xRadius: 2, yRadius: 2)
        palette.pausedBackground.setFill()
        bg.fill()

        let clamped = max(0, min(pct, 1))
        let fw = width * CGFloat(clamped)
        guard fw > 1 else { return }

        let fgRect = NSRect(x: x, y: y, width: fw, height: height)
        palette.pausedFill.setFill()
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
        // 有错误时显示红色感叹号
        if apiService?.lastError != nil {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 9),
                .foregroundColor: NSColor.systemRed
            ]
            "!".draw(at: NSPoint(x: bounds.width - 10, y: 2), withAttributes: attrs)
        }
    }

    private func drawBar(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat,
                         pct: Double, radius: CGFloat, palette: Palette) {
        let barRect = NSRect(x: x, y: y, width: width, height: height)

        // 背景
        let bg = NSBezierPath(roundedRect: barRect, xRadius: radius, yRadius: radius)
        palette.barBackground.setFill()
        bg.fill()

        let clamped = max(0, min(pct, 1))
        let fw = width * CGFloat(clamped)
        guard fw > 1 else { return }

        let fgRect = NSRect(x: x, y: y, width: fw, height: height)

        let color: NSColor
        if pct > 0.8 { color = palette.highUsage }
        else if pct > 0.5 { color = palette.midUsage }
        else { color = palette.lowUsage }

        if fw < radius * 2 {
            color.setFill()
            NSBezierPath(rect: fgRect).fill()
        } else {
            color.setFill()
            NSBezierPath(roundedRect: fgRect, xRadius: radius, yRadius: radius).fill()
        }
    }

    private var currentPalette: Palette {
        let textColor: NSColor = SettingsManager.shared.useBlackText ? .black : .white
        let secondaryColor: NSColor = textColor.withAlphaComponent(0.55)

        if isDarkMode {
            return Palette(
                barBackground: NSColor.white.withAlphaComponent(0.15),
                pausedBackground: NSColor.white.withAlphaComponent(0.08),
                pausedFill: NSColor.white.withAlphaComponent(0.25),
                lowUsage: .systemBlue,
                midUsage: .systemOrange,
                highUsage: .systemRed,
                primaryText: textColor,
                secondaryText: secondaryColor
            )
        }

        return Palette(
            barBackground: NSColor.black.withAlphaComponent(0.10),
            pausedBackground: NSColor.black.withAlphaComponent(0.05),
            pausedFill: NSColor.black.withAlphaComponent(0.15),
            lowUsage: .systemBlue,
            midUsage: .systemOrange,
            highUsage: .systemRed,
            primaryText: textColor,
            secondaryText: secondaryColor
        )
    }

    private var normalLayoutMetrics: (barX: CGFloat, barWidth: CGFloat, textX: CGFloat) {
        let leadingInset: CGFloat = 1
        let trailingInset: CGFloat = 0
        let gap: CGFloat = 2
        let textWidth = ceil(("100%" as NSString).size(withAttributes: [.font: Self.percentFont]).width)
        let textX = bounds.width - trailingInset - textWidth
        let barWidth = max(14, textX - gap - leadingInset)
        return (leadingInset, barWidth, textX)
    }

    private var pausedLayoutMetrics: (barX: CGFloat, barWidth: CGFloat, textX: CGFloat) {
        let leadingInset: CGFloat = 1
        let trailingInset: CGFloat = 0
        let gap: CGFloat = 2
        let textWidth = ceil(("⏸" as NSString).size(withAttributes: [.font: Self.pausedFont]).width)
        let textX = bounds.width - trailingInset - textWidth
        let barWidth = max(18, textX - gap - leadingInset)
        return (leadingInset, barWidth, textX)
    }

    private var isDarkMode: Bool {
        let appearance = appearance ?? NSApp.effectiveAppearance
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return true
        }
        return UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
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
    @State private var spinning = false

    var body: some View {
        VStack(spacing: 4) {
            QuotaRow(
                label: "5 小时用量", icon: "clock",
                pct: data.quota_5_hour.usage_percentage,
                used: data.quota_5_hour.used_flows,
                maxFlows: data.quota_5_hour.max_flows,
                usedUSD: data.quota_5_hour.used_value_usd,
                maxUSD: data.quota_5_hour.max_value_usd,
                resetsAt: data.quota_5_hour.resets_at
            )
            QuotaRow(
                label: "7 天用量", icon: "calendar",
                pct: data.quota_7_day.usage_percentage,
                used: data.quota_7_day.used_flows,
                maxFlows: data.quota_7_day.max_flows,
                usedUSD: data.quota_7_day.used_value_usd,
                maxUSD: data.quota_7_day.max_value_usd,
                resetsAt: data.quota_7_day.resets_at
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
                            api.resumeAutoRefresh()
                        } else {
                            api.pauseAutoRefresh()
                        }
                    } label: {
                        Image(systemName: api.isPaused ? "play.circle" : "pause.circle")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(api.isPaused ? .green : .orange)
                    .frame(width: 20, height: 20)
                    Button {
                        spinning = true
                        Task {
                            await api.refreshNow()
                            spinning = false
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14))
                            .rotationEffect(.degrees(spinning ? 360 : 0))
                            .animation(spinning ? .linear(duration: 0.6).repeatForever(autoreverses: false) : .default, value: spinning)
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
    let resetsAt: String?

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Image(systemName: icon).font(.caption).foregroundStyle(.blue)
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.2f%%", pct * 100))
                    .font(.caption).fontWeight(.medium).monospacedDigit()
                    .foregroundStyle(pct > 0.8 ? .red : pct > 0.5 ? .orange : .primary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(.primary.opacity(0.1)).frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(pct > 0.8 ? .red : pct > 0.5 ? .orange : .blue)
                        .frame(width: max(0, geo.size.width * pct), height: 4)
                }
            }
            .frame(height: 4)

            HStack {
                Text("已用 \(String(format: "%.2f", used))/\(String(format: "%.2f", maxFlows)) flows")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("$\(String(format: "%.2f", usedUSD)) / $\(String(format: "%.2f", maxUSD))")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            if let reset = resetsAt {
                HStack {
                    Text("重置 \(formatReset(reset))")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }

    private static let resetFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MM/dd HH:mm"; return f
    }()
    private static let resetIso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()

    private func formatReset(_ iso: String) -> String {
        guard let date = Self.resetIso.date(from: iso) else {
            return String(iso.prefix(16))
        }
        return Self.resetFmt.string(from: date)
    }
}
