<div align="center">

<img src="assets/readme/icon.png" alt="YamabikoChat 应用图标" width="128">

# YamabikoChat

**为 iPhone 与 iPad 打造的原生 AI 聊天工作台。**<br>
一个提示词，多个模型 —— 并排比较回答、让模型互相辩论，<br>
或将多个响应融合为一个最终结论。

[English](README.md) · [日本語](README.ja.md) · **简体中文**

[![Release](https://img.shields.io/github/v/release/porarrirr/yamabikochat?include_prereleases&display_name=tag)](https://github.com/porarrirr/yamabikochat/releases)
![Platform](https://img.shields.io/badge/iOS_·_iPadOS-17%2B-blue)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

</div>

---

**YamabikoChat**（山彦，意为"山谷回声"）是一个 SwiftUI 原生 AI 客户端，核心理念很简单：没有任何单一模型永远正确。与一个模型对话、让两个模型并排作答、让两个模型自主交谈，或运行完整的 面板 → 评判 → 合成 流水线 —— 一切尽在一个 App 中，在你的设备上完成。

> 仅支持 iOS 与 iPadOS。Android 版开发已结束，历史实现保留在 Git 记录中。默认开发分支为 `ios`。

## 截图

| 聊天 · 代码与数学公式 | GenUI 交互式回答 | 深色模式 | 会话库 |
|:-:|:-:|:-:|:-:|
| <img src="assets/readme/iphone-chat.png" width="200" alt="包含代码与数学公式的聊天"> | <img src="assets/readme/iphone-genui.png" width="200" alt="GenUI 贷款对比图表"> | <img src="assets/readme/iphone-dark.png" width="200" alt="深色模式下的 GenUI 组件"> | <img src="assets/readme/iphone-list.png" width="200" alt="带项目的会话列表"> |

| iPad 分屏视图 |
|:-:|
| <img src="assets/readme/ipad-split.png" width="560" alt="带侧边栏与聊天的 iPad 分屏视图"> |

## 功能

### 四种对话模式

- **聊天** —— 经典的一对一对话，支持流式回答、编辑/重新生成与响应变体。
- **双模型对比（Dual）** —— 同一提示词发送给两个模型，并排阅读两者的回答。
- **自动对话** —— 选定两个模型、话题与回合数，旁观它们彼此交谈。
- **Fusion** —— 问题并行发送给多个面板模型，评判模型生成结构化对比（共识、矛盾、独到见解、疑似错误），合成模型撰写最终回答。内置 quality / budget / fast 预设，并支持完全自定义 JSON。

### 提供商

| 提供商 | 连接方式 |
|---|---|
| Google Gemini | API 密钥或 Google 登录（OAuth） |
| ChatGPT 套餐 | 使用 OpenAI 账户登录 —— 直接使用你的 ChatGPT 订阅 |
| OpenAI | API 密钥 |
| OpenRouter | API 密钥 —— 可在 App 内浏览完整模型目录 |
| SuperGrok（xAI） | xAI 账户登录 |
| Z.ai · MiniMax | API 密钥 |
| OpenCode Go · ClinePass · Alibaba Coding Plan | 套餐凭据，App 内可查看用量 |
| Sarashina | API 密钥 |
| Apple Intelligence | 内置 —— 端侧与 Private Cloud Compute，无需密钥 |
| 自定义端点 | 任意 OpenAI 兼容的 base URL + 密钥 |
| models.dev 目录 | 通过按模型划分的通信契约解析更多提供商 |

模型身份与执行由内嵌的 [Pi Agents 运行时](ios/PiRuntime/) 负责解析 —— 不支持的模型会以明确原因保持可见但禁用状态，而不是擅自猜测通信协议。

### 客户端工具

- **网页搜索** —— 模型可在回答过程中调用 DuckDuckGo 联合搜索。
- **Python** —— 内嵌 Python 运行时执行模型编写的代码，并返回输出与文件。
- **GenUI** —— 模型可以用实时 UI 作答：原生渲染的交互式图表、卡片与 SVG 图形。
- **文件编辑器与用户询问** —— 结构化编辑与任务中途的澄清提问。

### 渲染

- Markdown（swift-markdown）、表格、带语法高亮与一键复制的代码块。
- MathJax 数学公式。
- 基于 CEL 表达式求值、具备交互能力的 GenUI 富文档。

### 为 iOS 与 iPadOS 而生

- **Siri、快捷指令与 App Intents** —— 对 Siri 说"向 YamabikoChat 提问"即可免手动发问，或在快捷指令中运行已保存的模型 / Fusion 预设。
- **Spotlight** —— 会话标题被索引、可搜索；屏幕内容上下文让 Siri 能针对你正在查看的会话执行操作。
- **私密会话** —— 完全排除在 Spotlight、Siri 与实体解析之外。
- **共享扩展** —— 从任意 App 将文本直接发送到新会话。
- **附件** —— 支持图片、PDF 与文本文件，单文件最大 10 MB。
- **组织管理** —— 项目、历史搜索、模型预设、逐条消息的 token 用量统计。
- **深色模式** 与 iPad 优化的分屏视图。
- UI 提供 English、日本語、简体中文、Español、Français 五种语言。

## 隐私与数据处理

- 提示词、请求中包含的会话上下文以及所选附件**仅会发送给你配置的提供商**。自定义端点与可选工具遵循其各自运营方的数据处理条款。
- API 凭据存储在 iOS 钥匙串中。
- Apple Intelligence 请求在端侧或通过 Apple Private Cloud Compute 处理。
- 内置诊断日志按类别与元数据记录网络/认证错误，可直接在 App 内查看 —— 无需 Xcode。

发送敏感内容前，请确认目标提供商、base URL 与已启用的工具。

## 下载

签名与未签名构建发布于 [GitHub Releases](https://github.com/porarrirr/yamabikochat/releases)。CI 生成的 iOS 产物可能未签名，不一定能直接安装到普通设备 —— TestFlight 分发由独立的手动工作流负责。

## 从源码构建

环境要求：macOS、Xcode 27、[XcodeGen](https://github.com/yonaskolb/XcodeGen)、Node.js 24。

```bash
cd ios
./bootstrap.sh        # 恢复依赖、构建 Pi、生成 Xcode 工程
open YamabikoChat.xcodeproj
```

运行测试套件：

```bash
cd ios && xcodegen generate
xcodebuild -project YamabikoChat.xcodeproj -scheme YamabikoChat \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' \
  CODE_SIGNING_ALLOWED=NO test
npm test --prefix ios/PiRuntime          # Pi 运行时测试
npm test --prefix ios/GenUIRuntimeTests  # GenUI DOM 测试
```

Bootstrap 缓存、构建目标与 CI 详情见 [ios/README.md](ios/README.md)。

## 仓库结构

| 位置 | 用途 |
|---|---|
| [ios/YamabikoChat/](ios/YamabikoChat/) | SwiftUI 应用 —— 功能模块、数据层、Pi 桥接、App Intents |
| [ios/YamabikoShareExtension/](ios/YamabikoShareExtension/) | 文本导入共享扩展 |
| [ios/YamabikoTests/](ios/YamabikoTests/) | 单元测试 |
| [ios/PiRuntime/](ios/PiRuntime/) | Pi Agents 运行时与 JS 测试 |
| [ios/docs/](ios/docs/README.md) | 开发笔记与设计 QA 资料 |
| [docs/](docs/README.md) | 公开网站 —— 隐私、支持、条款、Fusion 详解 |
| `scripts/` | 上游提供商契约检查 |
| `third_party/` | 第三方契约与许可声明 |

## 许可证

项目原创代码基于 [MIT License](LICENSE) 发布。附带及恢复的第三方软件遵循其各自的许可条款 —— 详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
