//
//  ZenmuxAPIService.swift
//  zenmux-monitor
//
//  Zenmux 管理 API 客户端
//  功能：获取订阅详情、用量配额等数据
//  接口：GET /api/v1/management/subscription/detail
//

import Foundation
import Observation

enum ZenmuxAPIErrorType: LocalizedError {
    case invalidURL
    case noAPIKey
    case networkError(Error)
    case httpError(Int)
    case decodeError(Error)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的 API 地址"
        case .noAPIKey:
            return "未设置 Management API Key，请在设置中配置"
        case .networkError(let err):
            return "网络错误: \(err.localizedDescription)"
        case .httpError(let code):
            return "HTTP 错误: \(code)"
        case .decodeError(let err):
            return "数据解析失败: \(err.localizedDescription)"
        case .apiError(let msg):
            return "API 错误: \(msg)"
        }
    }
}

@MainActor
@Observable
final class ZenmuxAPIService {
    static let shared = ZenmuxAPIService()

    private let baseURL = "https://zenmux.ai/api/v1/management/subscription/detail"

    var subscriptionData: ZenmuxSubscriptionData? {
        didSet { notifyStateChange() }
    }
    var lastError: String? {
        didSet { notifyStateChange() }
    }
    var lastUpdated: Date? {
        didSet { notifyStateChange() }
    }
    var isPaused = false {
        didSet { notifyStateChange() }
    }

    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var activeRefreshInterval: TimeInterval?
    @ObservationIgnored private var isManuallyPaused = false
    @ObservationIgnored var onStateChange: (@MainActor () -> Void)?

    // MARK: - 公开方法

    /// 按当前设置与监控状态重算刷新策略
    func refreshPolicyDidChange(forceFetch: Bool = false) {
        reconcileRefreshState(forceFetch: forceFetch)
    }

    /// 设置变更后重新加载监控状态并应用刷新策略
    func settingsDidChange(forceFetch: Bool = true) {
        ProcessMonitor.shared.refresh()
        reconcileRefreshState(forceFetch: forceFetch)
    }

    /// 手动暂停自动刷新
    func pauseAutoRefresh() {
        isManuallyPaused = true
        stopRefreshLoop(markPaused: true)
    }

    /// 手动恢复自动刷新
    func resumeAutoRefresh(forceFetch: Bool = true) {
        isManuallyPaused = false
        reconcileRefreshState(forceFetch: forceFetch)
    }

    /// 手动立即刷新一次，但不改变当前暂停状态
    func refreshNow() async {
        let shouldStayPaused = isManuallyPaused || !shouldAutoRefresh
        await fetchSubscription(force: true)
        if shouldStayPaused {
            isPaused = true
        }
    }

    /// 获取订阅详情
    func fetchSubscription(force: Bool = false) async {
        guard let apiKey = SettingsManager.shared.apiKey, !apiKey.isEmpty else {
            clearForMissingAPIKey()
            return
        }

        // 手动刷新绕过暂停检查
        if !force, isPaused { return }

        isPaused = false
        lastError = nil

        do {
            guard let url = URL(string: baseURL) else {
                throw ZenmuxAPIErrorType.invalidURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ZenmuxAPIErrorType.httpError(0)
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw ZenmuxAPIErrorType.httpError(httpResponse.statusCode)
            }

            let decoder = JSONDecoder()
            let result = try decoder.decode(ZenmuxSubscriptionResponse.self, from: data)

            if result.success, let subData = result.data {
                subscriptionData = subData
                lastUpdated = Date()
            } else {
                throw ZenmuxAPIErrorType.apiError(result.error?.message ?? "未知错误")
            }
        } catch let error as ZenmuxAPIErrorType {
            lastError = error.localizedDescription
        } catch {
            lastError = ZenmuxAPIErrorType.networkError(error).localizedDescription
        }
    }

    /// 兼容旧调用：恢复自动刷新
    func startAutoRefresh(interval: TimeInterval = 60) {
        activeRefreshInterval = interval
        isManuallyPaused = false
        startRefreshLoop(interval: interval, immediateFetch: true)
    }

    /// 兼容旧调用：暂停自动刷新
    func stopAutoRefresh() {
        pauseAutoRefresh()
    }

    private var shouldAutoRefresh: Bool {
        SettingsManager.shared.alwaysRefresh || ProcessMonitor.shared.isAnyMonitoredAppRunning
    }

    private func reconcileRefreshState(forceFetch: Bool) {
        guard let apiKey = SettingsManager.shared.apiKey, !apiKey.isEmpty else {
            clearForMissingAPIKey()
            stopRefreshLoop(markPaused: false)
            return
        }

        guard !isManuallyPaused else {
            stopRefreshLoop(markPaused: true)
            return
        }

        guard shouldAutoRefresh else {
            stopRefreshLoop(markPaused: true)
            return
        }

        let interval = SettingsManager.shared.refreshInterval
        startRefreshLoop(interval: interval, immediateFetch: forceFetch || subscriptionData == nil)
    }

    private func startRefreshLoop(interval: TimeInterval, immediateFetch: Bool) {
        let shouldRestartTask = refreshTask == nil || activeRefreshInterval != interval

        if shouldRestartTask {
            stopRefreshLoop(markPaused: false)
            activeRefreshInterval = interval
            refreshTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                    if Task.isCancelled { break }
                    await self?.fetchSubscription()
                }
            }
        }

        isPaused = false

        if immediateFetch {
            Task { [weak self] in
                await self?.fetchSubscription(force: true)
            }
        }
    }

    private func stopRefreshLoop(markPaused: Bool) {
        refreshTask?.cancel()
        refreshTask = nil
        activeRefreshInterval = nil
        isPaused = markPaused
    }

    private func clearForMissingAPIKey() {
        lastError = ZenmuxAPIErrorType.noAPIKey.localizedDescription
        lastUpdated = nil
        subscriptionData = nil
    }

    private func notifyStateChange() {
        onStateChange?()
    }
}
