# dsh-subagent-tools

为 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（dsh）提供增强版子代理委派工具：
**按次指定 model / provider / persona / toolFilter**、**`@preset:` persona 引用**、**`provider/model` 复合模型 id**——
以标准 **bundle** 形式交付，**不修改任何官方包文件**。

| [English](README.md) | [中文](README.zh.md) |

## 新增能力

官方 `subagent` / `subagent_fork` 工具只接受 `description` / `prompt` / `run_in_background`。本插件在不改变工具表面的前提下增加按次覆盖参数：

| 参数 | 作用 |
|---|---|
| `model` | 本次调用覆盖子代理的 LLM 模型。支持裸 id（`k3`）或复合 id（`kimi-code/k3`，同时切换 provider）。 |
| `provider` | 本次调用覆盖委派 provider（`spawn` / `fork` / ...）。 |
| `persona` | 本次调用覆盖子代理 persona——原文文本，或 `@preset:<id>` 引用已保存的 agent preset persona（按显示名或目录 id）。 |
| `toolFilter` | 本次调用覆盖子代理的工具 allow/deny 过滤。 |

所有覆盖项默认回落到实例配置，裸安装行为与官方工具完全一致。

## 安装

```sh
dsh plugin --profile web add dsh-subagent-tools          # npm
# 或：dsh plugin --profile web add github:lynx-gt/dsh-subagent-tools#main
# 或：dsh plugin --profile web add ./dsh-subagent-tools  # 本地目录
```

安装后重启 `dsh --profile web`。

### Web 会话：还要跑 preset 适配脚本（重要）

在 **web** profile 中，agent 工具由挂载的 agent **preset** 提供（默认 `standard`
preset 组合了 `subagent` / `subagent_fork`，指向 `@deepseek-ai/dsh-tool-subagent`），
**不是**由 host 平面提供。只靠 bundle patch 禁用官方行并插入自己的行，在 Web
会话里是**不可见**的——官方工具照常加载，本插件的按次覆盖参数根本不会出现
（headless 不需要这步，因为它的 agent 直接用 host 平面）。

运行 preset 适配脚本让 Web 会话使用本插件：

```sh
powershell -ExecutionPolicy Bypass -File install-preset.ps1   # Windows
# 或：./install-preset.sh                                     # POSIX
```

它会复制 `standard` preset 到 `$DSH_HOME/.agent-presets/standard-plus`，把其中的
`tool-subagent` / `tool-subagent-fork` 行改写为指向本包，并切换默认 preset。
然后**重启 `dsh web` 并新建会话**（preset 在会话创建时读取，运行中的会话无法切换）。
还原：在 UI（General > Agent preset）选回 `standard`，删除 `standard-plus` 目录即可。

> `headless` 及其他非 web profile 不需要这步。

### 让模型知道有哪些预设（`presetHints`）

`persona` 参数支持 `@preset:<id>` 引用，但工具 schema 不会列出你的机器上有哪些预设。
在工具行配置 `presetHints`（见 `cordis.patch.yml`）即可把它们注入 schema——模型会看到
"Available presets on this deployment: @preset:翻译员, ..." 并自行选用。不配则保持通用
（预设每台机器不同，写死会误导其他用户）。

### 兼容性

通过 `peerDependencies` 声明对公开 dsh 包（`^0.1.0-rc.6`）的依赖。若你的 dsh 版本超出兼容范围，pnpm
会报 peer 冲突并拒绝加载——升级本插件版本即可，而不是在静默损坏的 API 上运行。

## 示例

```
让子代理用 kimi-code/k3 模型 + 审校员 persona 干活：
  subagent(description="审校译文", prompt="...", model="kimi-code/k3", persona="@preset:审校员")
```

## 设计要点

- **标准 bundle，非补丁安装。** 本包是标准 dsh **bundle**（`dsh.bundle` manifest + `cordis.patch.yml`）：
  禁用官方 `tool-subagent` / `tool-subagent-fork` 行并插入自己的行——**不修改任何官方包文件**。
- **独立实现。** 工具基于公开 dsh API 编写（`defineTool`、`ctx.subagents.start` / `startContinuable`、`settleRun`），非官方源码 fork。
- **升级。** bundle 装在 profile 自己的 `node_modules`（pnpm symlink），dsh 升级不会移除它。但 dsh 处于
  developer preview（rc.6）：若升级改变公开 API，`peerDependencies` 会让插件显式拒绝加载（而非静默损坏）——
  此时升级本插件版本即可。
- **此处不含 `cwd` 参数。** 按次工作目录控制需要两处 dsh 安装内的进程内 subagent provider 补丁
  （前台 + 可继续子代理创建）。该能力在配套包 **`dsh-subagent-tools-cwd`** 中——它包含本插件的全部功能
  **加** `cwd` 参数 **加** 所需补丁。二选一安装，不要同时装。

## 已验证

在干净（无本地补丁）的 dsh `0.1.0-rc.6` Windows 环境实测（headless + web）：

- 按次 `model="kimi-code/k3"` 复合 id 路由 ✅
- 按次 `provider="fork"` 与原文 `persona` ✅
- `@preset:` 显示名（`@preset:审校员`）与目录 id（`@preset:translation-reviewer`）✅
- `presetHints` schema 注入 ✅
- Web profile：preset 适配脚本（`install-preset.ps1`）让 Web 会话使用本包工具 ✅（用上述 5 个预设实测）

## 限制

- **`@preset:` 依赖本地预设布局。** `$DSH_HOME/.agent-presets` 是 dsh 存放用户预设的位置，路径不是硬性
  公开契约，未来 dsh 版本可能改变发现方式；预设也因机器而异——`@preset:翻译员` 只在存在该预设的机器上可用。
- **Web 会话需要 preset 适配脚本。** dsh 自带的 `standard` preset 的委派行仍指向官方包；在跑
  `install-preset.ps1` / `install-preset.sh` 之前，Web 会话用的仍是官方工具（headless 等非 web profile 直接使用本包）。
- **`provider` 指子代理后端**，不是 LLM provider。要让子代理切换 LLM provider，用复合 `model` id
  （`kimi-code/k3`）或实例 `agentOptions`。

## License

MIT
