# OiiQT

用 iPhone 和 iPad 管理你的 qBittorrent、Transmission 和 MoviePilot。

OiiQT 使用 SwiftUI 构建，将多服务器任务管理、流量仪表盘、RSS 自动化和影视海报展示集中在一个客户端中。下载任务由你自己的服务器执行，手机用于查看和管理。

**无会员、无内购，不限制添加服务器的数量。** 扩展功能可在设置中自行开启。

[下载最新版本](https://github.com/gangz1o/OiiQT/releases/latest) · [构建记录](https://github.com/gangz1o/OiiQT/actions/workflows/release-ipa.yml) · [反馈问题](https://github.com/gangz1o/OiiQT/issues)

## 功能

| 模块 | 能力 |
| --- | --- |
| 多服务器管理 | 连接 qBittorrent、Transmission，切换服务器或聚合查看任务 |
| 下载任务 | 添加任务、搜索筛选、批量操作、查看文件、设置下载路径和限速 |
| 仪表盘 | 查看实时流量、上传下载统计、服务器状态、存储情况和近期完成任务 |
| RSS 自动化 | 管理订阅源、设置下载规则、匹配筛选条件并提交任务 |
| 影视信息 | 豆瓣与 TMDB 海报匹配、影视元数据、自定义 TMDB API Key |
| MoviePilot | 配置服务实例、浏览和搜索媒体、查看详情并提交下载 |
| 个性化 | 仪表盘模块配置、海报背景、Tracker 别名、隐藏节点名称、深浅色外观 |
| 配置同步 | 可选的 iCloud 配置同步 |
| 语言 | 简体中文、英文 |

不同下载器支持的操作有所差异，界面会根据服务器类型提供对应功能。

## 下载与安装

需要 **iOS / iPadOS 18.0 或更高版本**。

1. 打开 [Releases](https://github.com/gangz1o/OiiQT/releases)。
2. 在版本的 **Assets** 中下载 `OiiQT-unsigned.ipa`。
3. 使用自己的签名工具和账号签名后安装。

发布附件是未签名 IPA，不包含分发证书或描述文件，不能直接安装。iCloud 等系统能力取决于重新签名时使用的账号、描述文件与权限配置。

也可以通过 Xcode 从源码构建并安装到自己的设备。

## 开始使用

### 连接下载器

在「设置 → 服务器设置」添加服务器，选择 qBittorrent 或 Transmission，填写地址、端口和认证信息。

- 先开启下载器的 Web UI / RPC，并确保设备能够访问该地址。
- 使用反向代理时，按实际部署填写 HTTPS 和访问路径。
- 应用不会提供或托管下载服务器。

### 开启扩展功能

在「设置 → 扩展功能」中开启 TMDB 海报数据、全局任务聚合、仪表盘背景、隐藏节点名称或 iCloud 同步，也可以配置 Tracker 别名。

TMDB API Key 可在同一页面配置。当前版本保留内置服务配置，填写自己的 Key 后会优先使用自定义配置。

### 连接 MoviePilot

在「设置 → 扩展功能 → MoviePilot 设置」中添加实例并配置访问令牌。配置完成后，底部会显示 MoviePilot 页面。

### 使用 RSS

在「自动化」页面添加 RSS 源并配置下载规则；刷新间隔可在设置中调整。当前自动刷新在应用前台运行，切到后台后停止，不应将手机端作为全天候后台调度服务。

## 本地开发

### 环境

- macOS 与 Xcode；当前 CI 使用 **Xcode 26.6**。
- iOS 18.0 以上的模拟器或真机。
- Swift Package Manager 自动解析依赖，已锁定 Nuke 13.0.1。

### 打开项目

```bash
git clone https://github.com/gangz1o/OiiQT.git
cd OiiQT
open OiiQT.xcodeproj
```

等待依赖解析完成，选择 `OiiQT` Scheme 和设备后运行。真机安装需在 **Signing & Capabilities** 中选择自己的 Team、设置自己的 Bundle Identifier，并按账号支持情况配置项目中的 iCloud Key-value Storage 和 Push Notifications 权限。

### 命令行构建模拟器版本

先查看已有模拟器：

```bash
xcrun simctl list devices available
```

将下面的 `<UDID>` 替换为一个已有、兼容的模拟器 UDID：

```bash
xcodebuild \
  -project OiiQT.xcodeproj \
  -scheme OiiQT \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=<UDID>' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## 自动发布 IPA

工作流位于 [`.github/workflows/release-ipa.yml`](.github/workflows/release-ipa.yml)。

1. 将版本代码与工作流推送到 GitHub。
2. 基于包含工作流的提交创建标签，例如 `v1.0.1`。
3. 在 GitHub 发布正式 Release 或预发布 Release。
4. Actions 构建真机 Release 归档、打包未签名 IPA，并将 `OiiQT-unsigned.ipa` 上传到该 Release。

构建无需配置 Apple 证书或额外 Secrets，上传使用工作流自带的 `GITHUB_TOKEN`。应用版本号和构建号取自 Xcode 项目设置；发布前按需更新，标签不会自动修改这两个值。

也可以在 **Actions → Build unsigned IPA → Run workflow** 中手动构建。手动运行只生成 Actions Artifact，不创建 Release，也不向已有 Release 上传附件。

当前流程在 Release 发布后追加附件，因此需要允许修改已发布的 Release；若启用不可变 Release，应调整为先构建并上传到草稿，再发布。

## 项目结构

```text
OiiQT/
├── models/       数据模型、应用状态与下载器客户端
├── services/     影视数据、MoviePilot、凭据与同步服务
├── viewmodels/   页面状态与展示逻辑
├── views/        SwiftUI 页面和组件
├── utils/        解析与网络等辅助代码
└── Assets.xcassets/
OiiQT.xcodeproj/
.github/workflows/release-ipa.yml
```

## 反馈与贡献

欢迎通过 [Issues](https://github.com/gangz1o/OiiQT/issues) 提交问题或功能建议，也欢迎提交 Pull Request。

报告问题时请附上应用版本、系统版本、下载器类型与版本、复现步骤和相关截图。分享日志前请移除密码、访问令牌、RSS Passkey 等个人凭据。

## 许可证

当前仓库尚未添加 `LICENSE`，项目许可证待确定。
