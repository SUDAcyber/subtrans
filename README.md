# SUDA字幕翻译助手

## 使用前必读：安装、模型下载与常见问题

### 1. macOS 提示软件有风险或无法验证

当前发布包没有 Apple Developer ID 签名和公证，macOS 可能显示“无法验证开发者”、“Apple 无法检查其是否包含恶意软件”或软件有风险。请使用 Apple 官方允许的方式打开：

1. 将 `SUDA字幕翻译助手.app` 拖入“应用程序”文件夹。
2. 在 Finder 中按住 Control 点击或右键点击 App，选择“打开”，再次点击“打开”。
3. 如果仍被阻止，打开“系统设置 → 隐私与安全性”，滚动到“安全性”，在该 App 的提示旁点击“仍要打开”，使用 Touch ID 或管理员密码确认。

不需要也不建议关闭 Gatekeeper。下载后可使用 Release 附带的 `checksums.txt` 校验 DMG 的 SHA-256。

### 2. 系统、网络和磁盘要求

| 项目 | 要求或注意事项 |
| --- | --- |
| macOS | macOS 14.0 或更高版本 |
| 网络 | 首次安装 Typhoon、首次使用 WhisperKit、云端识别及 AI 翻译都需要网络 |
| Typhoon 空间 | 首次安装约需 2GB，依赖与 Python 环境保存在用户目录 |
| Whisper 空间 | 按选择的模型下载，`large-v3` 约 3.1GB；模型越大，首次下载和 Core ML 预热越慢 |
| 内存 | `large-v3` 识别时可占用约 2–3GB；任务结束并空闲 10 分钟后应用会卸载 pipeline |

Release 为了控制体积，不内置 Typhoon 或 Whisper 大模型；应用与安装器在 DMG 中，模型按需下载。

### 3. Typhoon ASR 本地泰语识别

- 用途：泰语本地识别，当前固定使用准确率优先的 Beam Search 4，速度会比原始 greedy 模式慢。
- 模型页：[Typhoon ASR Realtime](https://huggingface.co/typhoon-ai/typhoon-asr-realtime)
- 安装工具：[uv Releases](https://github.com/astral-sh/uv/releases/latest)
- 安装方式：在“设置 → 语音识别 → Typhoon ASR”中点击“一键安装 Typhoon”。
- 本地目录：`~/Library/Application Support/SUDA字幕翻译助手/typhoon/`
- 密钥要求：不需要 `.env`、API Key 或 Hugging Face Token；模型与安装器均为公开下载。
- 安装失败：先确认 GitHub 和 Hugging Face 可访问、磁盘空间足够，然后重试一键安装。如安装曾中断，可退出 App，删除上述 `typhoon` 目录后重新安装。
- 准确率注意：背景音乐、多人抢话、强口音和过低音量仍会导致错识；可用 WhisperKit `large-v3` 或 ElevenLabs Scribe 交叉对比。

### 4. WhisperKit 本地多语识别

- 模型仓库：[Argmax WhisperKit Core ML Models](https://huggingface.co/argmaxinc/whisperkit-coreml)
- 下载方式：在识别设置选择模型后导入音视频，首次使用会自动下载并显示进度。
- 密钥要求：公开模型不需要 `.env` 或 Hugging Face Token。
- 下载卡住：检查 Hugging Face 连接和磁盘空间；再次导入时 WhisperKit 会复用已完成的缓存。内存紧张时可选择 `small` 或 `medium`。
- 停止任务：点击“停止”会把取消状态传递到 Whisper 解码任务。

### 5. ElevenLabs Scribe 云端识别

- 官方文档：[ElevenLabs Speech to Text](https://elevenlabs.io/docs/capabilities/speech-to-text)
- 需要 ElevenLabs API Key，在 App 的识别设置中填写，密钥保存在 macOS Keychain，不会写入项目、DMG 或 `.env`。
- 音频会上传到 ElevenLabs 服务器并按其账户规则计费；不希望上传音频时请使用 Typhoon 或 WhisperKit。
- 大文件使用磁盘 multipart 流式上传，不会在内存中复制两份完整音频。

### 6. AI 翻译接口、密钥与数据

- 默认使用 AIHubMix 的 OpenAI 兼容接口，也可切换 OpenAI 或其他兼容 `/v1/chat/completions` / `/v1/responses` 的服务。
- API Key 仅保存在 macOS Keychain；项目源码、Release、DMG 和默认设置都不包含真实密钥。
- 字幕原文、剧情分析样本和翻译记忆会按所选接口发送到对应模型服务；如果内容敏感，请先确认服务商的隐私政策。
- Release 不预置任何个人翻译记忆。用户自行添加的记忆仅保存在本机偏好设置中。

### 7. 导入格式、MKV 与批量处理

- 支持 SRT 以及常见的 MP4、MOV、M4V、MP3、WAV、M4A、AAC、FLAC、AIFF、CAF 等音视频文件。AVI、OGG 等会按 macOS UTType 能力尝试进入媒体处理。
- MKV 不受 macOS AVFoundation 直接支持；请先用 ffmpeg 转为 MP4，或提取为 M4A/WAV 后导入。
- 多选时 SRT 会全部导入，媒体文件按队列依次识别和翻译。点击“停止”会取消当前任务并清空待处理队列。

### 8. 字幕导出与查找

- “导出原字幕”只导出识别原文和原始时间轴，不包含译文。
- “生成字幕/另存为”优先导出译文。
- 查找替换中的“定位下一处”会循环跳转、自动滚动并高亮匹配字幕。

SUDA字幕翻译助手是一个 macOS 字幕翻译工具，英文界面名为 SUDATranslator。软件默认使用中文界面和 AIHubMix 的 OpenAI 兼容接口，也可以切换到英文界面，或切换到任意兼容 `/v1/chat/completions` 或 `/v1/responses` 的大模型服务。

![UI concept](Docs/Concepts/subtitle-forge-ui-concept.png)

## 核心设计

- 本地解析 SRT：序号和时间轴不会交给模型重写。
- 分批翻译：按 cue 数量和字符预算切分，支持上下文重叠，避免超长文件一次性塞进模型。
- JSON 校验：模型必须按 cue id 返回译文，本地检查漏译和多译。
- 本地重建：导出时使用原始序号和时间轴，只替换字幕文本。
- 模型设置 Tab：密钥、接口地址、模型名、聊天补全/Responses、推理深度、输出长度和分段策略都可调整。
- 支持从 Finder 直接拖入一个或多个 `.srt` 文件。
- 后台记忆库 Tab：可保存人名、泰语名、术语等固定译法，每次翻译都会注入提示词。
- 译文查找替换：可搜索译文中的错误并替换一个或全部匹配项。
- 外观模式：默认跟随 macOS 深浅色，也可在工具栏或右侧设置里手动切换浅色/深色。
- 中英文界面：默认中文，可在右侧模型设置 Tab 的外观区域切换为 English。
- 翻译完成后会在原字幕文件夹下自动生成一个新版本，避免覆盖原文件。
- 历史记录支持移到回收箱，15 天后自动清理，也可以手动永久删除。
- 疑似未确认人名会在翻译完成后高亮提醒检查。

## 默认接口

```text
接口名称: AIHubMix
接口地址: https://aihubmix.com/v1
模型: gpt-5.5
接口模式: 聊天补全
```

密钥会写入 macOS Keychain，不会提交到 git。

## 记忆库

右侧设置面板可以维护固定译法，例如：

```text
原文专名 -> 目标语固定译名
```

发布版不预置任何记忆条目。用户添加的条目仅保存在本机偏好设置中。

## 长字幕处理流程

```mermaid
flowchart LR
  A["导入 SRT"] --> B["本地解析 cue id 和时间轴"]
  B --> C["按 cue 数量和字符预算分批"]
  C --> D["带前后上下文请求模型"]
  D --> E["解析 JSON 并校验 id"]
  E --> F["失败批次自动重试"]
  F --> G["本地重建 SRT"]
  G --> H["导出 UTF-8 SRT"]
```

## 运行

```bash
./script/build_and_run.sh
```

其他模式：

```bash
./script/build_and_run.sh --verify
./script/build_and_run.sh --logs
./script/build_and_run.sh --debug
```

## 测试

```bash
swift test
```

## 打包发布

生成 macOS `.app`、`.zip` 和 `.dmg`：

```bash
./script/package_release.sh 0.3.1
```

产物会输出到 `dist/release/`。如果本机没有 Developer ID 证书，脚本会使用 ad-hoc 签名，适合内部测试。正式发布时设置 `CODE_SIGN_IDENTITY` 和已保存的 `NOTARY_PROFILE`，脚本会自动签名、提交 Apple 公证并 staple 公证票据。

可选设置 `BUNDLE_WHISPER_MODEL_DIR` 把一个已下载的 WhisperKit 模型目录嵌入 App；未嵌入时，应用会在首次使用时显示实时下载进度。Typhoon 安装器随 App 分发，可在识别设置中一键安装。

## 版本管理

项目已经初始化为 git 仓库，主分支为 `main`。建议每次完成一个可验证能力后提交，例如：

```bash
git status
git add .
git commit -m "Add subtitle translation mac app scaffold"
```
