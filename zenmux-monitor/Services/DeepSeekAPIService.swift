//
//  DeepSeekAPIService.swift
//  zenmux-monitor
//
//  DeepSeek 余额查询 API 客户端
//  接口：GET https://api.deepseek.com/user/balance
//
//  设计：余额变化低频，采用「菜单打开时拉取」策略，
//  不接入 ProcessMonitor 条件刷新，不做后台轮询，零常驻开销。
//

import Foundation
import Observation

enum DeepSeekAPIError: LocalizedError {
    case invalidURL
    case noAPIKey
    case networkError(Error)
    case httpError(Int)
    case decodeError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的 API 地址"
        case .noAPIKey:
            return "未设置 DeepSeek API Key，请在设置中配置"
        case .networkError(let err):
            return "DeepSeek 网络错误: \(err.localizedDescription)"
        case .httpError(let code):
            return "DeepSeek HTTP 错误: \(code)"
        case .decodeError(let err):
            return "DeepSeek 数据解析失败: \(err.localizedDescription)"
        }
    }
}

@MainActor
@Observable
final class DeepSeekAPIService {
    static let shared = DeepSeekAPIService()

    private let baseURL = URL(string: "https://api.deepseek.com/user/balance")!

    /// 最近一次成功获取的余额数据
    var balanceData: DeepSeekBalanceResponse?
    /// 最近一次错误文案（成功后清空）
    var lastError: String?
    /// 最近一次成功更新时间
    private(set) var lastUpdated: Date?
    /// 是否正在请求
    private(set) var isRefreshing = false

    private init() {}

    // MARK: - 请求

    /// 拉取余额。无 Key 时静默置空（不报错），便于用户未配置时菜单不显示该区块。
    func fetchBalance() async {
        guard let apiKey = SettingsManager.shared.deepseekAPIKey,
              !apiKey.isEmpty else {
            // 未配置 Key：清空数据，不当作错误
            if balanceData != nil { balanceData = nil }
            lastError = nil
            return
        }

        guard !isRefreshing else { return }
        isRefreshing = true

        defer {
            isRefreshing = false
        }

        var request = URLRequest(url: baseURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw DeepSeekAPIError.httpError(http.statusCode)
            }
            let decoded = try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: data)
            balanceData = decoded
            lastError = nil
            lastUpdated = Date()
        } catch let error as DeepSeekAPIError {
            lastError = error.localizedDescription
        } catch {
            lastError = DeepSeekAPIError.networkError(error).localizedDescription
        }
    }
}
