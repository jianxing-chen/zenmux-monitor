# Zenmux Monitor

macOS 菜单栏小程序，实时显示 [Zenmux](https://zenmux.ai) API 用量配额。

## 功能

- **双进度条**：菜单栏直接显示 5 小时 / 7 天滚动窗口用量，菜单栏深浅随用量变化，下拉面板颜色随用量变化（蓝→橙→红），带精确百分比
- **重置时间圆环**：下拉面板每行用量右侧附圆环进度条，表示当前时间在该滚动周期内的占比——圆环转满即到 5 小时 / 7 天重置时刻，纯时间标度与用量进度相互独立；圆环颜色随时间推进同样蓝→橙→红渐变，菜单打开期间每分钟自动推进
- **7 天用量预测阴影**：7 天进度条上叠加半透明阴影，表示「若 5 小时用量被用满，7 天用量将达到的位置」——当前 7d 用量 + 5h 剩余可用量，露出主条右侧部分即预测增量；阴影颜色按预测值判档，提前预警（预测进入中/高档时阴影提前变橙/红）；5h 用满时预测=实际，阴影与主条重合不可见
- **DeepSeek 余额**：下拉面板独立区块显示 DeepSeek 账户余额（总余额、赠金、充值明细，支持 CNY/USD 多币种）；菜单打开时拉取，仅在设置中配置 DeepSeek API Key 后显示
- **下拉详情**：点击菜单栏图标展开完整用量面板（flows、USD、汇率、月度上限、到期时间）
- **条件刷新**：仅在指定 App（VS Code / Cursor / PyCharm 等）运行时才请求 API，空闲时零网络开销
- **自定义 App 列表**：设置中自由选择/添加哪些 App 触发刷新
- **始终刷新模式**：可选忽略 App 检测，全天候监控
- **暂停/继续**：菜单内一键暂停或恢复自动刷新
- **本地设置保存**：API Key 与所有配置持久化在应用本地
- **纯菜单栏运行**：无 Dock 图标，无窗口，极低资源占用

## 截图

<img src="screenshot.jpeg" width="320" alt="Zenmux Monitor 截图" />

> 截图仅为软件界面示意，图中数据均为虚例。

## 安装

1. 从 [Releases](../../releases) 下载 `zenmux-monitor.zip`
2. 解压后拖 `zenmux-monitor.app` 到 `/Applications`
3. 首次打开：**右键 App → 打开**（Ad Hoc 签名需绕过 Gatekeeper）
4. 之后可在系统设置 → 通用 → 登录项 中设为开机自启

## 配置

1. 点击菜单栏图标 → **设置**
2. 前往 [Zenmux 控制台](https://zenmux.ai/platform/management) 创建 **Management API Key**
3. 粘贴到设置窗口 → 保存
4. （可选）勾选需监控的 AI 编码工具
5. （可选）添加自定义 App 的 Bundle ID

## 系统要求

- macOS 15.0+
- Apple Silicon / Intel（通用二进制）

## 资源占用

- 内存：空闲 ~20MB，菜单打开时 ~30MB
- CPU：空闲时 < 0.1%，无轮询时 ≈ 0%
- 网络：仅监控 App 运行时每 60s 一次小请求

## 开发

```bash
git clone https://github.com/jianxing-chen/zenmux-monitor.git
cd zenmux-monitor
open zenmux-monitor.xcodeproj
```

Cmd+R 运行，Cmd+B 编译。

## License

MIT
