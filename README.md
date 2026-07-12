# SUDA字幕翻译助手

## 首次打开时 macOS 提示软件有风险或无法验证

当前发布包没有 Apple Developer ID 签名和公证，macOS 可能显示“无法验证开发者”、“Apple 无法检查其是否包含恶意软件”或软件有风险的提示。请使用 Apple 官方允许的方式打开：

1. 将 `SUDA字幕翻译助手.app` 拖入“应用程序”文件夹。
2. 在 Finder 中找到该 App，按住 Control 点击或右键点击，选择“打开”，再次点击“打开”。
3. 如果仍被阻止，打开“系统设置 → 隐私与安全性”，滚动到“安全性”，在该 App 的提示旁点击“仍要打开”，然后使用 Touch ID 或管理员密码确认。

不建议关闭 Gatekeeper 或修改全局安全设置。下载后可使用 Release 中的 SHA-256 校验文件确认 DMG 完整性。

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
