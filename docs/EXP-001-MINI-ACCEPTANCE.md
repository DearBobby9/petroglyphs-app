# EXP-001 · mini 直接桥接验收

日期：2026-10-16（America/Chicago）。

状态：已在 mini 的真实 ChatGPT Desktop 和 iPad Simulator 完成本机桥接、图文发送、原请求恢复及原生界面验收。真实项目的 HTTP 预览续接仍在运行；EXP-001 的主 Mac 物理离线、实体 iPad 网络路径与手动 Desktop UI 续接尚未验证，不能标记整体验收完成。

## 迁移前预检记录

以下为迁移前的历史预检状态；当前 mini 的运行结果见后文“mini 上已完成的运行验收”。

用户明确授权通过现有 Yobiru 向 mini 的 Codex 聊天发送隔离实验任务。
实验不替换现有服务，不修改配对、审批策略、账户或项目配置。

只读预检请求：`3dc275877b9615ef`。
该请求经历 `received → running → completed`，最终结果不是单纯收件回执。
报告附件为 `petroglyphs-exp001-preflight-3dc275877b9615ef.md`，7135 字节。
接收时已校验 SHA-256：
`a0551320e635b9b36802aae015a33b3ea89585a50c8f8725685004b919534221`。

| 检查项 | 本轮结果 | 证据边界 |
|---|---|---|
| 私有网络 | mini 在线；SSH 22 端口拒绝连接 | 不等于 Desktop 协议可用 |
| Desktop | 运行集成 Codex 的 ChatGPT Desktop `26.1013.31256` | 是否存在独立 `Codex.app` 不构成兼容性判断依据 |
| CLI | 实际 bundled CLI 为 `0.163.0-alpha.10.2`，登录正常 | 不记录账户标识或凭据 |
| 首次检查的 socket | `~/.codex/app-server-control/app-server-control.sock` 不存在 | 此路径并非项目使用的 IPC，不能据此判定功能不可用 |
| 现有桥接 | 3333 端口健康接口返回 200 | 仅证明旧服务存活 |
| 新接口 | `/api/bridge/identity` 与 `/api/codex/hosts` 均返回 404 | 旧服务不具备本轮目录和桥接身份能力 |
| 现有源码 | `948768fb708f4a01df4fc2e055f19bd1b844381a`，已有本地修改 | 未覆盖、重置或提交 mini 的既有修改 |
| 测试项目 | 本机目录没有独立 Petroglyphs 测试项目 | 未为验收擅自改变项目映射 |
| Node/npm | 可用独立 Node `v24.19.0`；已查路径中无 npm | 隔离运行可使用打包后的 JavaScript 与依赖 |

mini 的 CLI 路径：
`/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex`。

## 预检纠正

本轮源码使用 `$CODEX_HOME/ipc/ipc.sock`，未设置时为 `~/.codex/ipc/ipc.sock`。
首次预检没有检查该路径，且错误地将独立应用包作为前提。
用户纠正后已撤回该判断，并发出纠正预检请求 `5e2def2ee8fe6f75`。
纠正预检已完成：默认 IPC socket 为该用户所有、权限 `0600`，由 ChatGPT 主进程持有。
wrapper 与真实 binary 均为 `0.163.0-alpha.10.2`。
纠正报告 3616 字节，接收时 SHA-256 已核验：
`50cab563c2c8a05aaba3596e8659f853f81ed5ac67a26546149ec811a47e7581`。

纠正预检通过默认 schema 未见 `project/list`，但尚未运行临时 app-server。
父侧已核对 `generate-json-schema --help`：需要 `--experimental` 才包含实验方法。
生产客户端初始化使用 `experimentalApi: true`，不能用默认 schema 判定这些方法不存在。
本机通过项目现有 `CodexDesktopIpc.connect()` 完成了真实只读 initialize 握手。

## mini 上已完成的运行验收

后续使用独立端口 `3437`、独立 token 和 dataDir 启动临时 bridge；原常驻 `3333` 服务保持原进程，未修改配对、审批策略、账户或项目映射。

| 场景 | 已取得的结果 | 证据 |
|---|---|---|
| 真实项目创建与完整首条图文 | native 创建实际归属已有项目；一条 user message 同时包含完整文本与图片；标题和创建记录各只有一份。 | [mini 运行报告](MINI-RUNTIME-2026-10-16.md)；`build/mini-runtime/creation-final.json`、`project-membership-final.json` |
| 实际模型 | 原首回合历史确认 `gpt-6-luna`、`max`，无 reroute；conversation 与 creation 回执均为 confirmed。 | `build/mini-runtime/creation-final.json`、`conversation-final.json` |
| 断线与桥接重启 | HTTP 写入后断开客户端连接，再仅查询原 ID，恢复同一完成回合；运行中重启临时 bridge 后仍恢复同一 turn。没有重放发送。 | `build/mini-runtime/client-disconnect.json`、`disconnect-restart.json` |
| 本机停止与返回图片 | 同一 turn 并发 stop 幂等，旧 turn stop 不停止新 turn；结果 PNG 字节和 asset ID 在桥接重启后保持。 | [mini 运行报告](MINI-RUNTIME-2026-10-16.md) 的精确停止、图片恢复记录 |
| 原生 App 真实发送 | 在 iPad Simulator 画布绘图，向同一原聊天发送一条文本和一张图片（`c522…`），收起聊天后仍从 Running 更新到 Completed。 | `build/mini-simulator/original-request-running.png`、`conversation-round1-completed.json` |
| 原生编辑与创建草稿 | 五行输入、四图上限及添加禁用、图片缩放/切换/删除均实际操作；独立草稿标题与文本在 ResearchStart→JevCV 切换后保留，并可从列表取回。 | 父任务原生界面操作记录；[Simulator 验收报告](MINI-SIMULATOR-ACCEPTANCE-2026-10-16.md) |

自动 gate 取得 MCP 162/162、macOS Markdown/阅读位置 12/12、iPad 数据/网络 110/110 的通过结果，均为 0 fail、0 skip。iPad UI 四个场景分别取得通过证据：设置与大字体两项在 `build/checks/simulator-ui.gYmXtq/Results.xcresult`，修正菜单 helper 后的两项画布测试在 `build/checks/simulator-ui-scoped.afT640/Results.xcresult`。首次全套运行存在两项 helper 失败，未将其写成整轮全绿。逐 suite 的结果路径与修正说明见 [Simulator 验收报告](MINI-SIMULATOR-ACCEPTANCE-2026-10-16.md)。

生产 App 严格告警构建通过，记录在 `build/mini-manual-app-build.log` 与后续状态显示修复的 `build/mini-manual-status-build.log`，两次均启用 `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`。

## 真实项目预览续接与未完成边界

原生画布首轮 `c522…` 已在 ResearchStart 的 `build/petroglyphs-simulator-acceptance-20261016/index.html` 创建实际 HTML。该回合完成不代表预览成功：Chrome 注册阶段发生崩溃，浏览器又拒绝 `file:` 协议，因此首轮没有渲染结果图片。证据保存在 `build/mini-runtime/simulator-round1-preview-failure-evidence.json`。

用户随后明确授权 HTTP 方式。父任务为同一 scratch 目录启动临时 `127.0.0.1:3449` 服务，原聊天的 `f10…` 捕获了真实完整浏览器截图。模型手工转存 base64 未完成，父任务在 App 精确停止该回合，并从已经返回的浏览器工具结果逐字节保存实际 JPEG；未生成替代图。后续 `1c930b97…` 返回该图片，bridge 取回哈希与原浏览器字节一致。

App 已打开该结果、导入锁定底图并新增可编辑批注，固定为 r5 快照。第二轮 `f65f2030…` 向同一原聊天发送一条完整图文，原生历史仅一份；实际 HTML 只将按钮蓝色改为绿色，并在相同 HTTP 页面验证实际渲染。FEAT-001 软件闭环完成，包含模型转存失败后的人工恢复；详细哈希、回执及截图见 [Simulator 验收报告](MINI-SIMULATOR-ACCEPTANCE-2026-10-16.md)。

本轮没有物理断开主 Mac，没有实体 iPad/Pencil、掌面、硬件或浮动键盘、真实 VoiceOver 证据，也没有实体 iPad 的 Wi-Fi/Tailscale 路由验收。同一 Desktop owner 的 IPC 续接已验证；用户手动在 Desktop UI 输入续接尚未验证。远端审批、输入回答和未开放远端控制能力仍需独立验收。

mini 直接桥接应使用自己的配对身份。
它与主 Mac 经 companion 访问 mini 的路线不同，不能放入同一桥接的备用地址列表。

## 收尾与后续验收

1. 预览续接及同聊天批注回环已完成，保留截图、图文快照、实际代码与失败恢复证据。
2. 为主 Mac 离线、实体 iPad 网络路径和手动 Desktop UI 续接补齐各自实际证据。
3. 临时 `3437` bridge 与 `3449` HTTP 已停止、端口关闭；原 `3333` 仍由原 PID 96005 监听，未重启或替换。核对见 `build/mini-runtime/final-cleanup.json`。

App 的 63 个未发布提交已归并为 28 个问题提交，归并前后文件树完全相同。历史备份、映射及最终交付构建见 [Simulator 验收报告](MINI-SIMULATOR-ACCEPTANCE-2026-10-16.md)。后续新增 3 项 FIX-020 iPad 回归通过，App 累计 129 项不同测试取得通过证据。

隔离实验保留当前 ChatGPT Desktop、项目映射与常驻服务。
