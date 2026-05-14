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

    var subscriptionData: ZenmuxSubscriptionData?
    var lastError: String?
    var lastUpdated: Date?
    var isPaused = false

    private var refreshTask: Task<Void, Never>?

    // MARK: - 公开方法

    /// 获取订阅详情
    func fetchSubscription(force: Bool = false) async {
        guard let apiKey = SettingsManager.shared.apiKey, !apiKey.isEmpty else {
            lastError = ZenmuxAPIErrorType.noAPIKey.localizedDescription
            subscriptionData = nil
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

    /// 启动定时刷新
    func startAutoRefresh(interval: TimeInterval = 60) {
        isPaused = false
        stopAutoRefresh()
        refreshTask = Task {
            while !Task.isCancelled {
                await fetchSubscription()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    /// 停止定时刷新
    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        isPaused = true
    }
}
