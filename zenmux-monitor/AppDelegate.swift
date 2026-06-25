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

// MARK: - 用量配色（下拉面板统一蓝→橙→红三档）

/// 下拉面板中所有按「占比」变色的控件统一使用此配色，
/// 避免色值在 QuotaRow / ResetRing 等多处重复定义、改一处忘一处。
enum UsagePalette {
    /// 低占比（< 50%）：蓝
    static let low    = Color(red: 0.18, green: 0.56, blue: 0.98)
    /// 中占比（50% ~ 80%）：橙
    static let mid    = Color(red: 0.98, green: 0.67, blue: 0.19)
    /// 高占比（> 80%）：红
    static let high   = Color(red: 0.90, green: 0.34, blue: 0.31)

    /// 按占比返回对应档位颜色。
    static func color(for fraction: Double) -> Color {
        if fraction > 0.8 { return high }
        if fraction > 0.5 { return mid }
        return low
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let menuContentWidth: CGFloat = 336
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var processObservers: [NSObjectProtocol] = []
    private var appearanceObservers: [NSObjectProtocol] = []
    private var isShuttingDown = false
    private let apiService = ZenmuxAPIService.shared
    private let statusView = StatusBarView(frame: NSRect(x: 0, y: 0, width: 49, height: 22))

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        _ = ProcessMonitor.shared
        observeProcessMonitor()
        observeAPIService()
        observeAppearanceChanges()
        apiService.handleAppLaunch()
    }

    func applicationWillTerminate(_ notification: Notification) {
        let defaultCenter = NotificationCenter.default
        processObservers.forEach { defaultCenter.removeObserver($0) }
        processObservers.removeAll()

        let distributedCenter = DistributedNotificationCenter.default()
        appearanceObservers.forEach { distributedCenter.removeObserver($0) }
        appearanceObservers.removeAll()

        performShutdownCleanup()
    }

    // MARK: - 进程启停监听（App 运行时刷新，退出后停刷新）

    private func observeProcessMonitor() {
        let center = NotificationCenter.default

        let o1 = center.addObserver(forName: .monitoredAppDidLaunch, object: nil, queue: .main) {
            [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isShuttingDown else { return }
                self.apiService.appDidLaunch()
            }
        }

        let o2 = center.addObserver(forName: .monitoredAppDidTerminate, object: nil, queue: .main) {
            [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isShuttingDown else { return }
                self.apiService.refreshPolicyDidChange()
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
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.length = statusView.intrinsicContentSize.width

        statusView.apiService = apiService

        if let button = item.button {
            button.title = ""
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
        }
        statusItem = item
        updateStatusItemImage()

        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
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
        guard !isShuttingDown, let button = statusItem?.button else { return }
        statusView.appearance = button.effectiveAppearance
        button.image = statusView.renderedImage()
        button.needsDisplay = true
    }

    // MARK: - 菜单构建（懒加载）

    private func buildMenuItems(into menu: NSMenu) {
        let headerItem = NSMenuItem()
        let headerView = MenuHeaderView(apiService: apiService)
        let hosting = NSHostingView(rootView: headerView.frame(width: menuContentWidth))
        let headerSize = hosting.fittingSize
        hosting.frame = NSRect(x: 0, y: 0, width: menuContentWidth, height: headerSize.height)
        headerItem.view = hosting
        menu.addItem(headerItem)

        if let data = apiService.subscriptionData {
            let quotaItem = NSMenuItem()
            let quotaView = MenuQuotaView(data: data)
            let quotaHosting = NSHostingView(rootView: quotaView.frame(width: menuContentWidth))
            let quotaSize = quotaHosting.fittingSize
            quotaHosting.frame = NSRect(x: 0, y: 0, width: menuContentWidth, height: quotaSize.height)
            quotaItem.view = quotaHosting
            menu.addItem(quotaItem)
        } else {
            let loadingItem = NSMenuItem(title: "加载中...", action: nil, keyEquivalent: "")
            loadingItem.isEnabled = false
            menu.addItem(loadingItem)
        }

        menu.addItem(.separator())

        let actionItem = NSMenuItem()
        let actionView = MenuActionRow(
            onSettings: { [weak self] in self?.openSettings() },
            onRefresh: { [weak self] in self?.refreshData() },
            onQuit: { [weak self] in self?.quitApp() },
            isRefreshing: apiService.isRefreshing,
            hasAPIKey: !(SettingsManager.shared.apiKey?.isEmpty ?? true),
            isShuttingDown: isShuttingDown
        )
        let actionHosting = NSHostingView(rootView: actionView.frame(width: menuContentWidth))
        let actionSize = actionHosting.fittingSize
        actionHosting.frame = NSRect(x: 0, y: 0, width: menuContentWidth, height: actionSize.height)
        actionItem.view = actionHosting
        menu.addItem(actionItem)
    }

    private func openSettings() {
        guard !isShuttingDown else { return }
        if settingsWindow == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 580, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            win.title = "Zenmux 监控设置"
            win.contentView = NSHostingView(rootView: SettingsView())
            win.minSize = NSSize(width: 540, height: 640)
            win.center()
            win.isReleasedWhenClosed = false
            win.delegate = self
            settingsWindow = win
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func quitApp() {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        NSApplication.shared.terminate(nil)
    }

    private func refreshData() {
        guard !isShuttingDown, !apiService.isRefreshing else { return }
        Task { [weak self] in
            guard let self, !self.isShuttingDown else { return }
            await self.apiService.refreshNow()
        }
    }

    // MARK: - NSMenuDelegate（懒加载菜单）

    func menuWillOpen(_ menu: NSMenu) {
        guard !isShuttingDown else { return }
        if !menu.items.isEmpty { menu.removeAllItems() }
        buildMenuItems(into: menu)
    }

    func menuDidClose(_ menu: NSMenu) {
        guard !isShuttingDown else { return }
        menu.removeAllItems()
    }

    func windowWillClose(_ notification: Notification) {
        guard !isShuttingDown else { return }
        if let win = notification.object as? NSWindow, win == settingsWindow {
            win.contentView = nil
            settingsWindow = nil
        }
    }

    private func performShutdownCleanup() {
        isShuttingDown = true
        apiService.onStateChange = nil
        statusItem?.menu?.delegate = nil
        statusItem?.menu?.removeAllItems()

        if let win = settingsWindow {
            win.orderOut(nil)
            win.contentView = nil
            win.delegate = nil
            settingsWindow = nil
        }

        apiService.cleanup()
        ProcessMonitor.shared.cleanup()

        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }
}

// MARK: - 菜单栏自定义绘制视图

final class StatusBarView: NSView {
    weak var apiService: ZenmuxAPIService?

    private static let percentFont = NSFont.monospacedDigitSystemFont(ofSize: 9.2, weight: .regular)
    private static let pausedFont = NSFont.systemFont(ofSize: 7)
    private static let normalLeadingInset: CGFloat = 1.2
    private static let normalTrailingInset: CGFloat = 0.2
    private static let barTextGap: CGFloat = 0.4

    private static let percentRightPadding: CGFloat = {
        "0".size(withAttributes: [.font: StatusBarView.percentFont]).width * 0.35
    }()

    private static let percentTextReserveWidth: CGFloat = {
        max(
            "99.9%".size(withAttributes: [.font: StatusBarView.percentFont]).width,
            "100%".size(withAttributes: [.font: StatusBarView.percentFont]).width
        ) + StatusBarView.percentRightPadding
    }()

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
        NSSize(width: 49, height: 22)
    }

    func renderedImage() -> NSImage {
        let bounds = NSRect(origin: .zero, size: intrinsicContentSize)
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else {
            return NSImage(size: intrinsicContentSize)
        }

        cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: intrinsicContentSize)
        image.addRepresentation(rep)
        image.isTemplate = true
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

        let barH: CGFloat = 4.5
        let spacing: CGFloat = 4
        let topY = bounds.height - barH - 5
        let bottomY = topY - barH - spacing
        let corner: CGFloat = 2.25

        drawBar(x: layout.barX, y: topY, width: layout.barWidth, height: barH,
                pct: data.quota_5_hour.usage_percentage, radius: corner, palette: palette)
        drawBar(x: layout.barX, y: bottomY, width: layout.barWidth, height: barH,
                pct: data.quota_7_day.usage_percentage, radius: corner, palette: palette)

        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: Self.percentFont,
            .foregroundColor: palette.primaryText
        ]
        drawPercent(text: percentStr(data.quota_5_hour.usage_percentage),
                rightEdge: layout.textRightEdge, barRightEdge: layout.barRightEdge,
                barY: topY, barH: barH, attrs: textAttrs)
        drawPercent(text: percentStr(data.quota_7_day.usage_percentage),
                rightEdge: layout.textRightEdge, barRightEdge: layout.barRightEdge,
                barY: bottomY, barH: barH, attrs: textAttrs)
    }

    private func drawPaused(_ data: ZenmuxSubscriptionData) {
        let palette = currentPalette
        let layout = pausedLayoutMetrics
        let barH: CGFloat = 4.5
        let topY = bounds.height - barH - 5
        let bottomY = topY - barH - 2

        drawDimmedBar(x: layout.barX, y: topY, width: layout.barWidth, height: barH,
                      pct: data.quota_5_hour.usage_percentage, palette: palette)
        drawDimmedBar(x: layout.barX, y: bottomY, width: layout.barWidth, height: barH,
                      pct: data.quota_7_day.usage_percentage, palette: palette)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: Self.pausedFont,
            .foregroundColor: palette.secondaryText
        ]
        "⏸".draw(at: NSPoint(x: layout.textX, y: bottomY - 1), withAttributes: attrs)
    }

    private func drawDimmedBar(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat,
                               pct: Double, palette: Palette) {
        let barRect = NSRect(x: x, y: y, width: width, height: height)
        let bgPath = NSBezierPath(roundedRect: barRect, xRadius: 2, yRadius: 2)
        palette.pausedBackground.setFill()
        bgPath.fill()

        let clamped = max(0, min(pct, 1))
        let fw = width * CGFloat(clamped)
        guard fw > 0.5 else { return }

        NSGraphicsContext.saveGraphicsState()
        bgPath.addClip()
        let fillRect = NSRect(x: x, y: y, width: fw, height: height)
        palette.pausedFill.setFill()
        NSBezierPath(rect: fillRect).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func percentStr(_ pct: Double) -> String {
        let percent = (max(0, min(pct, 1)) * 1000).rounded() / 10
        if percent == 0 || percent == 100 {
            return String(format: "%.0f%%", percent)
        }
        return String(format: "%.1f%%", percent)
    }

    private func drawPercent(text: String, rightEdge: CGFloat, barRightEdge: CGFloat, barY: CGFloat, barH: CGFloat,
                             attrs: [NSAttributedString.Key: Any]) {
        let size = text.size(withAttributes: attrs)
        let y = barY + (barH - size.height) / 2
        let idealX = rightEdge - size.width
        let minX = barRightEdge + Self.barTextGap
        let drawX = max(minX, min(idealX, bounds.maxX - size.width))
        text.draw(at: NSPoint(x: drawX, y: y), withAttributes: attrs)
    }

    private func drawPlaceholder() {
        let palette = currentPalette
        let barH: CGFloat = 4.5
        let topY = bounds.height - barH - 5
        let bottomY = topY - barH - 4
        drawDimmedBar(x: 4, y: topY, width: 24, height: barH, pct: 0.45, palette: palette)
        drawDimmedBar(x: 4, y: bottomY, width: 24, height: barH, pct: 0.7, palette: palette)

        if apiService?.lastError != nil {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 9),
                .foregroundColor: NSColor.black
            ]
            "!".draw(at: NSPoint(x: bounds.width - 10, y: 2), withAttributes: attrs)
        }
    }

    private func drawBar(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat,
                         pct: Double, radius: CGFloat, palette: Palette) {
        let barRect = NSRect(x: x, y: y, width: width, height: height)
        let bgPath = NSBezierPath(roundedRect: barRect, xRadius: radius, yRadius: radius)

        // 1. 背景层
        palette.barBackground.setFill()
        bgPath.fill()

        // 2. 填色层：用背景路径裁剪，填色自然继承左/右圆角
        let clamped = max(0, min(pct, 1))
        let fw = width * CGFloat(clamped)
        guard fw > 0.5 else { return }

        let color: NSColor
        if pct > 0.8 { color = palette.highUsage }
        else if pct > 0.5 { color = palette.midUsage }
        else { color = palette.lowUsage }

        NSGraphicsContext.saveGraphicsState()
        bgPath.addClip()
        let fillRect = NSRect(x: x, y: y, width: fw, height: height)
        color.setFill()
        NSBezierPath(rect: fillRect).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private var currentPalette: Palette {
        Palette(
            barBackground: NSColor.black.withAlphaComponent(0.18),
            pausedBackground: NSColor.black.withAlphaComponent(0.12),
            pausedFill: NSColor.black.withAlphaComponent(0.28),
            lowUsage: NSColor.black.withAlphaComponent(0.58),
            midUsage: NSColor.black.withAlphaComponent(0.76),
            highUsage: NSColor.black.withAlphaComponent(0.94),
            primaryText: NSColor.black,
            secondaryText: NSColor.black.withAlphaComponent(0.55)
        )
    }

    private var normalLayoutMetrics: (barX: CGFloat, barWidth: CGFloat, barRightEdge: CGFloat, textRightEdge: CGFloat) {
        let leadingInset = Self.normalLeadingInset
        let trailingInset = Self.normalTrailingInset
        let gap = Self.barTextGap
        let textWidth = Self.percentTextReserveWidth
        let textRightEdge = bounds.width - trailingInset
        let textX = textRightEdge - textWidth
        let barWidth = max(13, textX - gap - leadingInset)
        let barRightEdge = leadingInset + barWidth
        return (leadingInset, barWidth, barRightEdge, textRightEdge)
    }

    private var pausedLayoutMetrics: (barX: CGFloat, barWidth: CGFloat, textX: CGFloat) {
        let leadingInset: CGFloat = 4
        let trailingInset: CGFloat = 4
        let gap: CGFloat = 5
        let textWidth: CGFloat = 7
        let textX = bounds.width - trailingInset - textWidth
        let barWidth = max(18, textX - gap - leadingInset)
        return (leadingInset, barWidth, textX)
    }
}

// MARK: - 菜单 Header 视图

struct MenuHeaderView: View {
    let apiService: ZenmuxAPIService

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            leftSummary
            Spacer(minLength: 8)
            rightActions
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private static let dateFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MM/dd"; return f }()

    private func formatDate(_ iso: String) -> String {
        guard let date = iso.iso8601Date else { return String(iso.prefix(10)) }
        return Self.dateFmt.string(from: date)
    }

    @ViewBuilder
    private var leftSummary: some View {
        if let data = apiService.subscriptionData {
            let status = ZenmuxAccountStatus.from(data.account_status)
            VStack(alignment: .leading, spacing: 3) {
                Text("Zenmux \(data.plan.tier.capitalized)")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor(status))
                        .frame(width: 6, height: 6)
                    Text(status.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("到期 \(formatDate(data.plan.expires_at))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text("未连接")
                    .font(.subheadline.weight(.semibold))
                if let err = apiService.lastError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    private var rightActions: some View {
        HStack(spacing: 8) {
            if let updated = apiService.lastUpdated {
                Text("更新于 \(relativeTime(updated))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                if apiService.isPaused {
                    apiService.resumeAutoRefresh()
                } else {
                    apiService.pauseAutoRefresh()
                }
            } label: {
                Image(systemName: apiService.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .foregroundStyle(apiService.isPaused ? .green : .orange)
            .accessibilityLabel(apiService.isPaused ? "恢复自动刷新" : "暂停自动刷新")
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "\(seconds)秒前" }
        if seconds < 3600 { return "\(seconds / 60)分前" }
        return "\(seconds / 3600)时前"
    }

    private func statusColor(_ s: ZenmuxAccountStatus) -> Color {
        switch s {
        case .healthy: .green
        case .monitored: .yellow
        case .abusive: .orange
        case .suspended, .banned: .red
        case .unknown: .gray
        }
    }
}

// MARK: - 菜单配额视图

struct MenuQuotaView: View {
    let data: ZenmuxSubscriptionData

    var body: some View {
        VStack(spacing: 12) {
            QuotaRow(
                label: "5 小时用量", icon: "clock",
                pct: data.quota_5_hour.usage_percentage,
                used: data.quota_5_hour.used_flows,
                maxFlows: data.quota_5_hour.max_flows,
                usedUSD: data.quota_5_hour.used_value_usd,
                maxUSD: data.quota_5_hour.max_value_usd,
                resetsAt: data.quota_5_hour.resets_at,
                windowDuration: 5 * 3600
            )
            QuotaRow(
                label: "7 天用量", icon: "calendar",
                pct: data.quota_7_day.usage_percentage,
                used: data.quota_7_day.used_flows,
                maxFlows: data.quota_7_day.max_flows,
                usedUSD: data.quota_7_day.used_value_usd,
                maxUSD: data.quota_7_day.max_value_usd,
                resetsAt: data.quota_7_day.resets_at,
                windowDuration: 7 * 24 * 3600
            )

            HStack(spacing: 10) {
                compactMetricCard(
                    title: "当月上限",
                    value: "\(formatNum(data.quota_monthly.max_flows)) flows",
                    detail: "$\(formatNum(data.quota_monthly.max_value_usd))",
                    icon: "chart.bar.fill",
                    tint: .purple
                )
                compactMetricCard(
                    title: "汇率",
                    value: "$\(String(format: "%.4f", data.effective_usd_per_flow))",
                    detail: "per flow",
                    icon: "dollarsign.circle.fill",
                    tint: .green
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    private func formatNum(_ v: Double) -> String {
        v >= 10000 ? String(format: "%.2fk", v / 1000)
                   : String(format: "%.2f", v)
    }

    private func compactMetricCard(title: String, value: String, detail: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(tint)
            Text(value)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }
}

struct QuotaRow: View {
    let label: String; let icon: String
    let pct: Double; let used: Double; let maxFlows: Double
    let usedUSD: Double; let maxUSD: Double
    let resetsAt: String?
    let windowDuration: TimeInterval

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Label(label, systemImage: icon)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.2f%%", pct * 100))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(progressColor)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.10))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(progressColor)
                        .frame(width: max(0, geo.size.width * pct), height: 8)
                }
            }
            .frame(height: 8)

            HStack {
                Text("已用 \(String(format: "%.2f", used))/\(String(format: "%.2f", maxFlows)) flows")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("$\(String(format: "%.2f", usedUSD)) / $\(String(format: "%.2f", maxUSD))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if let reset = resetsAt {
                HStack(spacing: 6) {
                    Text("重置 \(formatReset(reset))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    ResetRing(resetsAt: reset, windowDuration: windowDuration)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }

    private static let resetFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE MM/dd HH:mm"; return f
    }()

    private func formatReset(_ iso: String) -> String {
        guard let date = iso.iso8601Date else {
            return String(iso.prefix(16))
        }
        return Self.resetFmt.string(from: date)
    }

    private var progressColor: Color {
        UsagePalette.color(for: pct)
    }
}

// MARK: - 重置时间圆环（当前时间在滚动周期内的占比）

/// 纯时间标度：圆环转满 = 窗口重置时刻（`resetsAt`）到达。
/// 滚动窗口周期长度固定（5h / 7d），窗口起点 = `resetsAt - windowDuration`，
/// 已过占比 = `(now - 起点) / 周期时长`，随时间推进线性增长，到 `resetsAt` 时为 100%。
struct ResetRing: View {
    let resetsAt: String
    let windowDuration: TimeInterval

    /// 当前时间在周期内的占比，取值 [0, 1]。
    private func fraction(at now: Date) -> Double {
        guard let end = resetsAt.iso8601Date else { return 0 }
        // now 已到/过重置时刻 → 周期已满
        guard now < end else { return 1 }
        let start = end.addingTimeInterval(-windowDuration)
        let f = now.timeIntervalSince(start) / windowDuration
        return min(max(f, 0), 1)
    }

    var body: some View {
        // 菜单打开期间每分钟推进一次，避免百分比/圆环长时间停留不动。
        // 仅在此视图存活（菜单打开）时计时，关闭即随视图释放而停止，零常驻开销。
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let fraction = fraction(at: context.date)
            let color = UsagePalette.color(for: fraction)
            HStack(spacing: 3) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.12), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(
                            color,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.3), value: fraction)
                }
                .frame(width: 12, height: 12)
                Text(String(format: "%d%%", Int(fraction * 100)))
                    .font(.system(size: 9, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }
        }
        .help("周期时间进度：圆环转满即到重置时刻")
    }
}

// MARK: - 菜单底部操作按钮行

struct MenuActionRow: View {
    let onSettings: () -> Void
    let onRefresh: () -> Void
    let onQuit: () -> Void
    let isRefreshing: Bool
    let hasAPIKey: Bool
    let isShuttingDown: Bool

    var body: some View {
        HStack(spacing: 0) {
            actionButton(
                icon: "gearshape.fill",
                label: "设置",
                action: onSettings,
                disabled: isShuttingDown
            )

            Divider()
                .frame(height: 16)

            actionButton(
                icon: "arrow.clockwise",
                label: isRefreshing ? "刷新中" : "刷新",
                action: onRefresh,
                disabled: !hasAPIKey || isRefreshing || isShuttingDown
            )

            Divider()
                .frame(height: 16)

            actionButton(
                icon: "power",
                label: "退出",
                action: onQuit,
                disabled: false
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }

    private func actionButton(icon: String, label: String, action: @escaping () -> Void, disabled: Bool) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(height: 16)
                Text(label)
                    .font(.system(size: 9, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? .tertiary : .secondary)
        .disabled(disabled)
        .accessibilityLabel(label)
    }
}
