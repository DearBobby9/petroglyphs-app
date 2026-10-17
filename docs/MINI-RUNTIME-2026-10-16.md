# mini MCP 运行验收与提交归并

日期：2026-10-16（America/Chicago）。运行记录使用 UTC，最后核对时间为 2026-10-17 04:22。

本轮在 mini 的真实 ChatGPT Desktop 上完成了本机项目创建、完整首条图文、模型证据、HTTP 客户端断线、桥接进程重启、精确回合停止及返回图片固化。运行服务采用独立端口 3437、独立 token 和独立 dataDir，legacy worker 关闭。原 3333 服务的进程保持不变。

## 真实运行结果

| 场景 | 结果与证据 |
|---|---|
| 当前安装版本 | ChatGPT Desktop `26.1013.31256`，build `20586`；bundled CLI `0.163.0-alpha.10.2`。Codex 集成在 ChatGPT Desktop。 |
| 本机目录 | 配对 API 成功读取本机已保存项目与 7 个模型。未修改项目映射、账户或审批设置；在现有项目创建专用无操作测试聊天。 |
| 本机原生创建 | `creationMethod=native`；真实 native project membership 已确认；创建的聊天出现在同一已保存项目，测试标题计数为 1，私有 native 创建记录计数为 1。 |
| 首条图文 | 完整说明和一张 99 字节 PNG 同属一条 user message；原文、图像 URL 字节及原 request ID 在 Desktop 历史中一致。模型返回指定确认文本。 |
| 实际模型 | 首回合原生历史证据为 `gpt-6-luna`、`max`、无 reroute。最终 conversation receipt 与 creation receipt 均为 `modelVerification=confirmed`。 |
| 客户端断线 | 第二条无操作消息通过 HTTP 写入后关闭客户端连接，未读取响应。之后仅按原 ID GET 状态，得到同一已完成回合；没有重新 POST。 |
| 运行中重启 | 第三条消息取得真实 turn ID、回执处于 queued 后，对临时桥接执行 SIGKILL，再以相同 token/dataDir 启动。Desktop 的同一回合仍在运行，桥接恢复后可读取并停止它。 |
| 精确停止 | 两个并发 stop 请求绑定同一 host/thread/turn，返回相同 `stopped` 回执与观察时间。真实历史随后显示该 turn 为 interrupted。 |
| 过期停止 | 下一回合运行时，对旧 turn 的 stop 返回 `already_finished`，新回合 ID 保持 active；随后用新 turn ID 成功停止，历史显示 interrupted。 |
| 返回图片 | 第一个模型样本抄错 base64，后端显示 `invalid_image`。第二个 68 字节 PNG 样本完整返回，投影成配对 asset，下载字节与固定样本完全一致。 |
| 图片重启恢复 | 最终桥接重启后，结果 message ID、asset 路径和字节保持不变；SHA-256 为 `6b1048f8a6d40bac0b2954c18fefa40c4ea7a96120fc2e54b7317c0e43c2bbec`。 |
| 最终去重 | 同一测试聊天共有 5 条有意发送的 user message；首条 request ID 仅出现 1 次，首条仍有 1 张附件，原聊天 ID 保持一致。 |
| 最终诊断 | `compatibility=baseline_match`，host probe 为 `verified_read`，build/source commit 均为 `3b10145e17d0d258933ce3fb4af8c47a934e3b48`，sourceDirty 为 false。 |

上述后续回合通过同一个真实 Desktop owner 的 IPC 执行，证明本机接管与同一聊天续接。未将这些结果记为用户手动在 Desktop 输入的 UI 验收。

## 本轮补齐的代码

- **FEAT-001**：显式图片结果转为配对资源；限制 PNG/JPEG、单张 10 MiB、单消息四张和 24 MiB；本机读取限定到经过核对的聊天工作目录或当前聊天 generated_images 目录；远端路径不会当成本机文件读取。首次成功字节持久化，HTTP 投影隐藏图片源地址并保留不可用原因、遗漏数量。
- **FIX-027**：增加 mini 的精确安装包基线。匹配必须同时满足 Desktop 版本、build、ASAR SHA-256 和 bundled CLI 版本。仍保留原安装包基线；不同或缺失任一身份字段均不匹配。停止能力还需要针对真实 owner 的无副作用协商。
- **FIX-014**：创建已完成后，status GET 可以更新原首回合的模型证据。只接受同 host、同 thread、同 firstTurnId 的有效证据；未知、冲突或不可读结果不能降级或改绑已完成创建，也不会再次创建、打开或发送。修复了真实运行中 creation receipt 长期显示 unverified、conversation receipt 已确认模型的差异。
- **FIX-028**：统一 gate 与 CI 的原改动保留。根目录 CLAUDE.md 现在明确区分当前持久化、固定画布背景、显式清空操作和历史 V1 说明，避免旧文档重新引入已移除手势。

## 安装包契约证据

实际 ASAR SHA-256：`bf9c41fa9770fbfacfba93042ff71c24cb65c82935819377275faac08103383f`。

限定检查的安装包 JavaScript 成员：

| 成员 | SHA-256 |
|---|---|
| `.vite/build/src-DsLVGakC.js` | `28a0918f01c50b0eb17676e894998ad7182f119d978adf0467ccaac3583f259c` |
| `webview/assets/app-initial-3ccf4886957f.js` | `d6278b4127345cf6012fe969eea9f5a2d55a13225d1fcadc23db81ef5bab78fe` |

成员中的版本表为 snapshot 11、read settings 1、load history 1、start turn 2、interrupt turn 4，带 host 路由的 follower 方法版本偏移为 1。停止 handler 在 expectedTurnId 与当前 inProgress turn 不匹配时直接返回 null；这一契约另由真实 owner 的随机过期 turn 探测和两次真实停止验证。

使用 reverse-engineer-anything 的只读 CLI 分析保留了聚焦证据 `ev_d8c90e07a0b6028e9b83e1798c178b06833609d738ea3ea1c7dbe98ff90be05e`。完整 ASAR 的首次分析遇到一个 unpacked native 成员声明哈希与现有字节不一致，不能用作全包完整性结论；后续结论限定到上述提取成员、记录的源包哈希和真实 IPC 调用。静态图不作为执行成功证据。

## 自动检查与历史归并

| 检查 | 结果 |
|---|---|
| FEAT-001 接线后的统一 MCP gate | 160/160 通过。 |
| mini 兼容基线回归 | 新回归先复现未匹配失败；修复后 diagnostics、execution-controls、desktop-ipc 共 39/39 通过。 |
| 创建完成后的模型证据回归 | 新回归先复现 unverified 未更新；修复后 projects、native-creator、conversations 共 57/57 通过。 |
| 最终统一 MCP gate | `npm test`：162/162 通过，0 fail、0 skip；Node `v24.19.0`。 |
| 历史归并后 | 重新构建 dist 成功。未重复运行文件树完全相同的测试。 |

仅归并基线 `4e3d3f916932be8035a17abf9276f75069da4732` 之后的本轮本地提交，17 个提交归并为 11 个问题提交；未 push。

备份分支：`backup/mini-mcp-before-grouping-20261016`，归并前 HEAD 为 `ac5bc4228699ece077735b457f629153d58b438c`。

归并前后最终文件树均为 `7cc82afa1ccc0b851560c8890c880899c74a70e1`，Git 工作区清洁。

| ID | 最终 commit |
|---|---|
| FIX-001 | `a78fe0794ee446a876cfc486d665f9d44fca991d` |
| FIX-007 | `17e3c7a24e592a54d59da67979fd44e65c63ca3f` |
| FIX-008 | `376f4c617624fd466a72dd891be7b54ed74d673b` |
| FIX-027 | `8b45f36e1b6cf9eef7ce973f3fc0109823239ad1` |
| FIX-014 | `2999447cde5da6a55b5b8245598392e8540a67c8` |
| FEAT-002 | `829529e969710a7b85ebcbe837899d49d7cc2cbd` |
| FIX-026 | `f7f7ab4456747392a60ab016981af6070bc5eaeb` |
| FIX-023 | `7ae9bc4d70bad14a71abb797945745f37cdc99a3` |
| EXP-002 | `83d8f3f08f1c46b0c742fa72997cdf12596a10a9` |
| FEAT-001 | `bc002261dc264f548c06c4209d39e425c1613b34` |
| FIX-028 | `3b10145e17d0d258933ce3fb4af8c47a934e3b48` |

完整 old→new 映射保存在忽略目录 `build/mini-runtime/mcp-history-map.json`。

## 证据位置与边界

私有运行数据位于 App 的忽略目录 `build/mini-runtime/`，目录权限 0700，私有配置与运行证据文件权限 0600。配对 URL、token、实际项目路径和测试聊天 ID 保留在该目录，未写入本报告。`runtime-private.json` 记录当前临时 PID/config/dataDir，`private-url.txt` 供本机 iPad Simulator 使用；最终交接时临时 PID 为 134。

主要证据文件：`npm-final-gate.log`、`diagnostics-mini-red.log`、`diagnostics-mini-green.log`、`creation-model-red.log`、`creation-model-green.log`、`creation-final.json`、`conversation-final.json`、`client-disconnect.json`、`disconnect-restart.json`、`stop-a-receipts.json`、`stop-stale-evidence.json`、`result-valid-asset.json`、`final-runtime-summary.json`、`project-membership-final.json`、`mcp-history-map.json`。静态分析压缩证据为 `rea-ipc-evidence.json.gz`。

临时桥接继续运行供父任务的 Simulator 验收使用。旧 3333 服务保持原进程；最终本机检查为旧服务 PID 96005、临时服务 PID 134。

本轮没有物理断开主 Mac，也没有实体 iPad、Apple Pencil、硬件或浮动键盘证据。临时桥接只绑定本机 loopback，没有进行 iPad Wi-Fi/Tailscale 路由验收。EXP-001 的“主 Mac 离线 + iPad 实际操作 + Desktop 手动续接”整体验收仍需这些对应证据。

返回图像验证使用无操作测试回复，尚未完成 FEAT-001 所要求的“真实项目画 UI → 修改代码 → 查看结果 → 底图批注 → 同一聊天第二轮修改”完整任务。审批与输入回答继续显示 Desktop 处理位置；本轮没有宣称远端 stop 或这些未开放能力已可用。
