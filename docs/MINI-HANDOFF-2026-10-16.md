# Petroglyphs 整改：迁往 mini 的交接

日期：2026-10-16（America/Chicago）。

## 当前决定

用户已要求停止 MacBook Pro 上的实现、测试和构建。
本机只完成进度记录、传输与校验。后续开发全部在 mini 进行。
mini 没有连接实体 iPad，先用 iPad Simulator 完成所有可行验收。
不得把模拟器结果写成 Pencil、真机键盘或实际 iPad 验收。

本机实现代理已全部中断，并完成只读交接。
本轮未运行生产 App 整合构建，未运行 MCP 新统一全套 gate，未 push、部署或整理历史。

## 必须保留的任务要求

1. 完成 [统一修改与验收清单](REVIEW-REMEDIATION-PLAN.md) 中全部 28 个 FIX、2 个 EXP、2 个 FEAT。
2. 一个问题一个 commit。同问题在两个仓库可各有一个提交；本仓库的分层提交和 fixup 最终须按 ID 归并。
3. 不丢失现有 Git 历史、未提交修改、未跟踪源码及测试证据。不得覆盖 mini 上已有的 dirty 仓库。
4. 当前中间提交尚未按 ID 归并。迁移阶段保留原样，待代码修完并通过相关 gate 后只整理本轮未发布历史。
5. 不 force-push、merge、发布或替换常驻服务。当前任务授权实现、验证和本地 commits。
6. 遇到困难先查当前版本、真实接口与可行解决路径，尝试可验证的修复，再报告真正剩余的阻塞。
7. Codex 已集成在 ChatGPT Desktop。不得把独立 `Codex.app` 是否存在作为兼容性条件。
8. 采用真实代码与当前安装版本证据，不能用 source、mock、构建或 schema 代替运行成功。
9. unknown 不自动重放。请求 ID 固定目标、图文快照和模型。先保存真实 thread ID，再接管与发送。
10. 桥接身份独立于地址；两台机器不能放入同一桥接备用地址列表。
11. 改动先读相关代码和测试。针对 bug 的新回归先稳定复现失败，再修复并检查通过。
12. 验证保持比例。成功检查在相关代码或环境改变前有效，不重复跑作信心检查。最多一波正常 review。
13. 设计、复杂实现、诊断与规划用 GPT-6 Astra/max。方法与验收完全确定的机械执行才用 GPT-6 Luna/max。
14. 代理按明确文件边界分工，不回退别人修改；父代理负责整合和最终 gate。
15. 中文进展简明、事实明确。最终说明改动、验证、剩余风险，不加泛泛后续邀请。

## 两仓库冻结点

| 仓库 | 本轮基线 | 暂停时 HEAD |
|---|---|---|
| petroglyphs-app | `c79d811f5a73c927f7cdf6f900e9862691c7c2ea` | `1594fc0c6569ecaeec691df841c3e83f1a2924a6` |
| petroglyphs-mcp | `4e3d3f916932be8035a17abf9276f75069da4732` | `20301e01d790191123b61c6da5f2e3089099fb0e` |

完整提交列表、tracked/untracked 文件 SHA-256、工作树状态与 patch 随迁移包保存。
两仓库均有未提交内容，不能仅 clone HEAD 后开始工作。

## 已实现内容与现有证据

以下为中断时的实现与 targeted check 结果，均不代表整合验收已完成。

| 范围 | 已有结果 | 后续限制 |
|---|---|---|
| FIX-001 | 后端持久解除 unknown 等待、pending 取消、晚到关联；App 队列操作已接。后端写盘失败放行已修为先保存后更新内存 | fixup 未归并；无 cached receipt 的 unknown 操作入口尚需核对 |
| FIX-002/004 | 原生画布文档、固定背景、ID/版本/范围、保存保护、100 步进程内撤销/重做、同步清空；危险手势移除 | Canvas 最终 17 项通过；实际页面、手势和 Pencil 仍待验收 |
| FIX-003 | 草稿/请求与历史独立恢复，损坏文件保护；3 项 targeted tests 通过 | 同一 review 波已发现版本和重复 ID 风险，见下节 |
| FIX-005 | 历史 503 时独立核对 receipt、在途 POST 保护、不重 POST；3 项通过 | 整合构建未做 |
| FIX-006 | generation/cursor 防旧分页写入；150 条补齐、重启、交叠刷新 3 项通过 | Simulator 阅读恢复仍待验收 |
| FIX-007 | 持久单调入队序号；同毫秒、逆 UUID、回拨与重启 targeted tests 通过 | 旧同毫秒记录仅承诺稳定排序 |
| FIX-008 | 官方 tool 结果先持久化，再独立核验目标；冲突仍 unknown | 原相关 43 项及追加持久证据测试通过；实际 companion 未验收 |
| FIX-009/010/011 | 首条消息持久 handoff、独立草稿 ID、改目标保留输入、多草稿检索与原记录保留；相关 targeted tests 通过 | UI 整合未 build；按 ID 合并分层提交 |
| FIX-012/014 | 画布固定快照加入完整消息；本机 native 首条图文持久与恢复；创建附件/移交 4 项通过 | 官方 remote companion 无图片参数且空 prompt 被拒绝，不伪造支持 |
| FIX-013 | 请求引用在 POST 返回前保存，重启/切换保持原目标；1 项通过 | 原请求跨目标持续 polling 尚未实现 |
| FIX-015/016 | 实测内容限高、空间预算、紧凑模式，焦点不改布局；Layout 7 项通过 | 大字体、短窗口、软件/浮动键盘组合待 Simulator |
| FIX-017/019 | Foundation 完整 Markdown parser、turn 过程折叠、稳定 block ID 与块内比例；Markdown 4 项、阅读位置 2 项、持久化 1 项通过 | 旋转/懒加载/重排实际恢复待 Simulator |
| FIX-018 | 草稿/消息共用缩放、平移、多图与固定快照预览 | 待运行检查细节与只读状态 |
| FIX-020 | 发送证据、执行状态、模型证据分离，异常与 Desktop 处理入口 | 真实等待/失败/运行组合待验收 |
| FIX-021/023 | 离线最近聊天、明确 projectId/projectName、空目录创建入口 | 最近聊天持久化 1 项和后端上下文 2 项通过；UI 仍待 build |
| FIX-022 | 目标可用性刷新与旧异步响应隔离；2 项通过 | 数据层尚未提交，UI 已提交 |
| FIX-024/025 | 设置本地编辑、Save 提交、Cancel 丢弃、测试绑定配置；工作区原地修复连接 | FIX-024 仅语法解析，需运行表单竞态/取消流程 |
| FIX-026 | 配对/身份/目录脱离 legacy worker，旧恢复错误不阻断新接口；相关测试通过 | 新统一 gate 尚未运行 |
| FIX-027 | 后端诊断/去敏样本已提交，App DTO/VM/UI 已写 | App 数据层诊断测试未跑且未提交；build stamp 见下节 |
| FIX-028 | App 旧根目录 35 文件已清理，统一脚本已加入；Reconnect 8 项通过 | MCP npm test/CI/README 尚未提交；新测试 manifest 尚需整合 |
| EXP-001 | mini 真实 IPC 已确认；已发送隔离运行包 | 旧预检的独立 Desktop 判断错误已撤回；旧实验需安全收尾后换完整仓库 |
| EXP-002 | 2000 turn 合成样本，snapshot 约 5.05 MB、50 消息响应约 47.9 KB；owner/revision 转换缓存正确性通过 | 本机合成中位约 24.180→9.155 ms，上游每轮读取仍存在；不作设备/网络收益承诺 |
| FEAT-001 | 锁定底图、来源/版本、选区与合成导出；消息预览及 Files/Photos 导入入口已写 | 后端模块尚未写，当前接线 import 指向缺失文件，不能宣称可构建 |
| FEAT-002 | 精确 host/thread/turn 停止，当前 owner 的 v4 无效回合协商；35 项相关测试通过 | 实际本机 no-op 协商通过，未停止真实回合；远端能力未验证时不开放，审批/输入仍 Desktop 处理 |

### 当前未提交文件归属

App：

- FIX-022：`Petroglyphs/App/AppState.swift`、`ViewModels/CodexTargetAvailabilityModel.swift`、`Tests/CodexTargetAvailabilityTests.swift`、`Tests/projects.yml`。
- FIX-027：`Models/CodexBridgeDiagnostics.swift`、`Services/NetworkService+Diagnostics.swift`、`ViewModels/CodexDiagnosticsModel.swift`、`Tests/CodexDiagnosticsTests.swift`、`Tests/conversation.yml`。
- FEAT-001：`Models/CodexConversation.swift` 的 `unavailableReason` 与 `omittedResultImageCount`。
- FIX-028：`README.md`、`scripts/check.sh`、`Tests/project.yml`。
- 本次交接文档、EXP-001 记录与统一清单更新属于迁移记录。

MCP：

- FIX-028：`package.json`、`package-lock.json`、`README.md`、`.github/workflows/ci.yml`。
- FEAT-001：`src/codex-conversation-history.ts`、`src/codex-conversations.ts` 已接线，但 `src/codex-result-images.ts` 尚不存在。子代理中断前没有创建模块、测试或文档。

### 首先修复的明确缺口

1. FIX-003：恢复版本只允许已定义的 1/2，不能继续接受 0/负数；载入 outgoing 和 receipts 前验证 ID 唯一，避免 `Dictionary(uniqueKeysWithValues:)` fatal；异常仍保护原文件，历史错误不阻塞草稿。新回归先失败再修。
2. FIX-013：按 `CodexConversationKey` 在 Store 内共享 polling task/订阅，让工作区原请求卡观察原目标；不能选到 B 后停止 A 的核对，也不能建立另一套轮询状态机。
3. FIX-001 UI：unknown 且本地没有 receipt 时，“解除等待”入口现在可能调用后直接 return。应由后端验证原请求，不能显示无效操作。
4. FEAT-001：完成缺失后端模块与 targeted tests，再检查接线。UI 还需显示不可用原因和 omitted 数量。
5. FEAT-001/014：画布加入新建草稿时，UI 除 `request == nil` 外还需检查附件能力和数量；数据层已有拒绝保护。
6. FIX-027：运行新增诊断测试并提交；生产构建时将构建源 SHA 写入 `PetroglyphsSourceCommit`。不能用当前源码 SHA 冒充已经安装的 App SHA。
7. FIX-028：`Tests/project.yml` 已加入 CanvasDocument，后续 CanvasDocumentReference 依赖还需纳入；统一 `scripts/check.sh` 已加入 canvas/markdown，markdown 为 macOS XCTest。

### FEAT-001 后端已约定的契约

```ts
resultImageInputs(item): ResultImageInput[]

new CodexResultImages({ dataDir, codexHome? }).attachments(
  { hostId, threadId, messageId, cwd?, inputs },
  persistAssetCallback
): { attachments, omittedAttachmentCount }
```

已核验当前 schema/安装代码中的 imageGeneration、tool 直接图像数据与明确 Markdown 图片结果。
仅处理 PNG/JPEG，最多 4 张、单张 10 MiB、总 24 MiB。
本机读取限于已核验 cwd 或 `CODEX_HOME/generated_images/<threadId>`，防 symlink 逃逸。
远端路径不得读成本机文件。成功首次读取须固化 bytes，刷新/重启不跟随源文件变化。
代码示例不触发读取；原始路径和 URL 不返回 HTTP。详情参考随包保留的代理交接补充。

## mini 接续流程

1. 将完整交接包存入新 staging 目录。核对 archive SHA-256、逐文件 manifest、两个 Git bundle 与 HEAD。
2. 为两个仓库创建相邻 checkout，保留原 tracked/dirty/untracked 状态。不得覆盖 mini 现有源码或其本地修改。
3. 读本文件、统一清单、各 repo README 和完整交接补充。先查看本机 Xcode/Simulator、Node 与当前 ChatGPT runtime。
4. 完成上述明确缺口，按问题分组提交。先跑对应 regression；不要对未改动成功覆盖重复检查。
5. 完成后按 ID 归并本轮未发布提交，保留原冻结点和 SHA 对照。处理实际冲突，不混入别的问题。
6. App 生产 build；MCP 统一 `npm test` 最终 gate。修具体编译/行为错误后只复查受影响部分。
7. 启动独立临时 bridge，用 mini 当前 ChatGPT Desktop 中 Codex 的真实 IPC/native API 验收。
8. 安装到 iPad Simulator，逐项完成统一清单第 9 节可做的界面和端到端场景。
9. 明确区分 source、targeted test、整合 build、Simulator、真实 Desktop/远端执行与物理 iPad 证据。
10. 更新清单状态与完成记录。停止测试 server、关闭任务专属调试目标，报告每问题最终 commit 与剩余真机项。

模拟器优先检查：画布导航/重启与可编辑恢复、清空后画新笔迹再撤销、固定图文一次发送、首条移交、草稿改目标/检索、附件放大、短窗口/大字体/五行输入/四图、长回复中段旋转/键盘/分隔条、离线聊天切换、设置 A 测试中改 B 后取消、原请求状态卡、正确停止回合。

mini 没有实体 iPad。不得为等待设备而停止其他可做的模拟器、故障注入和 Desktop 验收。

## 当前 runtime 与 mini 实验线索

- 实际 Desktop 是 ChatGPT.app 中的 Codex。
- IPC：`$CODEX_HOME/ipc/ipc.sock`，默认 `~/.codex/ipc/ipc.sock`。
- wrapper：`/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex`。
- binary：`/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex`。
- mini 预检版本：ChatGPT `26.1013.31256`，CLI `0.163.0-alpha.10.2`。
- schema 应用 `app-server generate-json-schema --experimental`；native initialize 用 `experimentalApi: true`。
- 本轮本机实际 IPC initialize 成功，精确 owner 的停止能力 no-op 协商成功。这些不是 mini 的真实发送证据。
- 官方 create_thread runtime 要求 `prompt.min(1)`，空字符串在创建前被拒绝；内部 startWithoutFirstTurn 没通过该工具开放。
- mini 原桥接在 3333，旧仓库 dirty，不替换它。新独立 bridge 采用新 dataDir、新 token、新临时端口。
- 临时 paired config：`deviceToken/codexPath/dataDir`；`PETROGLYPHS_BRIDGE_CONFIG`，可设 `PETROGLYPHS_LEGACY_SUBMISSIONS=0` 独立关闭旧 worker。
- 原隔离实验 request：`792a7dfaea7c3e9e`，运行包来自 MCP `abe1c605e160b5f8efeea58315ceececf66c2158`，不是本次完整 dirty 工作树。
- 已发 notice `01876dc32d8d47ff`，要求安全收尾旧实例后等待完整迁移，不在旧 snapshot 继续开发。

## 证据保留

迁移包包含本轮 `/tmp/petroglyphs-{fix*,feat*,canvas*,ui-*}` 日志、相关 xcresult、App `build/checks` 结果和 EXP-001 去敏报告。
不复制 DerivedData 编译缓存、旧运行服务的凭据或用户私人聊天内容。
完整 Git 状态和 commit 对照由迁移脚本生成，随包保存以核对交接。
