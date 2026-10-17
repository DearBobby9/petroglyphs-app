# mini App 与 iPad Simulator 验收

日期：2026-10-16（America/Chicago）。

本报告区分源码、故障回归、构建、模拟器和真实 Desktop 证据。没有实体 iPad 或 Apple Pencil；模拟器输入不能替代 Pencil、掌面、硬件键盘、浮动键盘或真实 VoiceOver 操作证据。

## 环境与可重复入口

- Xcode 27.1（27A9275），从当前 mini 的 App Store 安装；Apple 协议经用户明确同意后接受。
- iOS 27.1（24A94425）是仅支持 iPhone Duo 的专用运行时；不能将其写为 iPad 验收环境。iPad 使用标准 iOS 27.0（24A434）。
- XcodeGen 2.46.0；生产工程为 `Petroglyphs.xcodeproj`，生产源码为 `Petroglyphs/`。
- 测试命令为 `scripts/check.sh`。`markdown` 使用 macOS，其余数据与 UI 测试使用 iPad Simulator。
- 本机使用 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` 与 `PETROGLYPHS_DERIVED_DATA_ROOT=/tmp/PetroglyphsChecks`。后者只改变编译产物位置，避免 macOS XCTest 从 Desktop 打开 bundle 时阻塞；日志与 xcresult 仍保存在仓库 `build/checks/`。
- UI 测试用独立的 `com.bobbyjia.petroglyphs.acceptance` 容器，编译同一套生产视图、模型和资源。模拟器允许触控绘图，实体设备仍为 `.pencilOnly`。
- 数据测试在 iPad 13 英寸模拟器 `C163F7B7-3319-416C-BDDE-367D3BBFFFD9` 串行执行；UI 测试在独立 iPad 11 英寸（M4）模拟器 `D1A21072-9F2B-4B2E-9CC0-FF883B0C4A81` 执行，均为 iOS 27.0。

## 本轮补齐的行为

| ID | 补齐内容 |
|---|---|
| FIX-001 | 本地 unknown 消息没有缓存回执时仍向后端请求解除等待；后端保留最终校验权，失败不会抹掉原请求。 |
| FIX-003 | 聊天状态、历史和创建草稿只接收明确的版本 1/2；重复 outgoing/receipt ID 进入保护恢复，避免 Dictionary fatal。创建列表保留不能解码的恢复入口。 |
| FIX-013 | Store 按完整会话键共享轮询，状态卡订阅原目标；切换 A→B 仍核对 A，重复订阅不重复轮询，后台取消订阅。 |
| FIX-014 | 新建草稿的画布入口检查附件能力和四图上限；远端不支持首条图片时有明确原因。创建完成后模型证据可从原首回合更新，且不重放发送。 |
| FIX-017 | 阅读模式由实测滚动位置更新，覆盖非触控滚动；恢复等待原 Markdown 块出现，避免先将块内比例应用于整条消息。 |
| FIX-020 | native `final_answer` 与旧 `final` 都显示完成；已拿到真实 turn ID 的停止/未知回合显示已送达，同时明确回复完成仍未确认，工作区状态与消息行一致。 |
| FIX-022 | 按当前目标刷新机器和聊天可用性，过期异步结果不能覆盖新的选择。 |
| FIX-027 | App 诊断接线、目标/版本校验、真实构建源 commit 写入 Info.plist；后端增加经过实际安装包和运行验证的 mini 基线。 |
| FIX-028 | 全部 XCTest 与 UI 测试统一入口；补全画布依赖；修复生产 Swift 并发边界与 CoreGraphics 导入；当前文档不再引导恢复已删除手势。 |
| FEAT-001 | 结果图片的 unavailable 原因与省略数量可见；正确解码后端 `omittedAttachmentCount`，兼容早期缓存；不可用图片不能批注。 |

其余修复沿用迁移包中的实现，并由本轮整合 gate 验证。

## 已取得的证据

| 层级 | 结果 | 证据 |
|---|---|---|
| 修复前/后回归 | Store、创建版本与非触控滚动的新问题均先复现失败，再验证修复。便携 Store 断言执行 31 个方法；创建版本的真实 macOS XCTest 修复前 52 个断言失败，修复后 2 个测试通过。 | `build/mini-regressions/` |
| 真实 macOS XCTest | Markdown 4 项、阅读位置 8 项，12/12 通过，0 fail、0 skip。 | `build/mini-markdown-tmp.log`；`build/checks/markdown.gNNo7x/Results.xcresult` |
| App 生产构建 | 修复 CoreGraphics 导入及并发边界后，生产 App 在 `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` 下通过；后续状态显示修复的源码快照也通过。 | `build/mini-manual-app-build.log`（source commit `12aa90d52aca1daaed4538b93c80fe6445e3affe`）；`build/mini-manual-status-build.log`（`f461a60bf70693a3b1fd3ef8e2df07fd1f100dda`） |
| iPad 数据/网络 XCTest | 五个 suite 串行执行，合计 110/110 通过，0 fail、0 skip。 | 下表逐项列出 xcresult；每个目录同时保留 `xcodebuild.log`。 |
| iPad UI XCTest | 四个场景均取得实际运行通过证据：首轮设置与大字体两项通过；修正测试定位后重跑两项画布测试，2/2 通过。 | `build/checks/simulator-ui.gYmXtq/Results.xcresult`；`build/checks/simulator-ui-scoped.afT640/Results.xcresult` |
| 真实 bridge/Desktop | MCP 最终 162/162；本机完整首条图文、原模型、断线/重启、精确停止与结果图片持久化通过。 | [独立运行报告](MINI-RUNTIME-2026-10-16.md) |

| iPad suite | 通过数 | 失败 / 跳过 | 结果文件 |
|---|---:|---:|---|
| 画布文档 | 17 | 0 / 0 | `build/checks/canvas.C0efNP/Results.xcresult` |
| 聊天、Store 与附件 | 43 | 0 / 0 | `build/checks/conversation.vcak8D/Results.xcresult` |
| 项目与创建 | 35 | 0 / 0 | `build/checks/projects.80BVsk/Results.xcresult` |
| 布局 | 7 | 0 / 0 | `build/checks/layout.6bLX4k/Results.xcresult` |
| 重连 | 8 | 0 / 0 | `build/checks/reconnect.Z9iRFw/Results.xcresult` |

macOS 与 iPad 数据测试合计 122 项。上述数字不包括另列的四项 UI 场景或 MCP 的 162 项测试。

随后实际停止场景发现 FIX-020 的送达文案仍不准确。新增 3 项 iPad 回归先执行并产生 24 条预期断言失败；失败后 Xcode 收集诊断阻塞，已停止仅属本任务的诊断进程，因此修复前 xcresult 不完整，不当作完整 gate。日志为 `build/mini-fix020-before.log`。修复后仅运行新增 3 项，3/3、0 fail、0 skip，通过结果为 `build/checks/conversation.4F4cT3/Results.xcresult` 与 `build/mini-fix020-after.log`。最终累计为 125 项数据/模型测试加 4 项 UI 场景，即 129 项不同 App 测试取得通过证据；未重复执行未受影响的通过项。

## 场景证据与边界

| 实际 UI 场景 | 结果 |
|---|---|
| 画布持久化 | 通过。离线打开已有工作区，选择 Warm paper，以模拟器触摸绘图；Home→工作区及终止→重启后，原笔迹和固定背景均恢复；新笔迹仍可撤销。 |
| 清除后的编辑历史 | 通过。画 A→清除→画 B→撤销 B 得到空白→撤销清除恢复 A→重做清除为空白→重做 B 恢复 B。截图确认恢复的是对应笔迹。 |
| 连接编辑与取消 | 通过。在本机模式将 URL 改为 `http://127.0.0.1:9/test-a` 并测试，再改为 `http://127.0.0.1:9/test-b`，旧结果及进度清除、测试按钮恢复；切换模式后 Cancel，重开仍为原保存地址与模式。未向外部云地址发起测试。 |
| 大字体、旋转与背景 | 通过。Accessibility XXXL 下横竖屏控制可达；主题切换后 Warm paper 固定背景保持；连接设置的 Cancel 可达。此项不等于真实 VoiceOver 操作。 |

UI 首轮中设置与大字体两项通过，画布两项在绘图前因测试用 Escape 未关闭 iPad 菜单失败。改为点击菜单外部后，画布测试继续到撤销步骤，暴露系统 PencilKit 工具栏与应用菜单同名 Undo 的定位冲突。根据实际层级改为 `collectionViews.buttons` 后，两项画布测试均通过。两种失败各进行一次有证据的修正；未重跑不受这些 helper 改动影响的已通过场景。不能将首轮整份 xcresult 写成四项全绿。

最终画布运行截图在 `build/checks/simulator-ui-scoped.afT640/attachments/`，索引为 `manifest.json`；设置与大字体截图在 `build/checks/simulator-ui.gYmXtq/all-attachments/`。测试代码与模拟器输入适配提交为 `6879ac8`（归并前）。

## 原生 App 与真实 bridge 的人工操作

以下为父任务在原生 App 中的实际操作，结合私有 bridge 回执核对；不计入上述四项 XCTest。

| 场景 | 当前证据与结果 |
|---|---|
| 真实画布发送 | 在画布绘制并向原聊天发送一条文本加一张图片，请求 `c522…`。原聊天保持一致；收起聊天后状态仍由 Running 更新为 Completed。`build/mini-simulator/original-request-running.png` 与 `conversation-round1-completed.json` 保留过程及完成回执。 |
| 长输入与四图上限 | 五行长文本输入可用；加入四张图片后继续添加入口禁用。原生图片预览的缩放、下一张和删除均实际操作。证据为父任务原生界面操作记录。 |
| 独立创建草稿 | 创建草稿的标题和文本在目标 ResearchStart→JevCV 切换后保留，返回后能从草稿列表取回。证据为父任务原生界面操作记录；未将草稿检查写成已创建第二个聊天。 |
| 真实项目首轮修改 | `c522…` 在 ResearchStart 的 `build/petroglyphs-simulator-acceptance-20261016/index.html` 创建实际 HTML。首轮已完成，但 Chrome 注册阶段崩溃，且浏览器拒绝 `file:` 协议，未得到渲染预览。`build/mini-runtime/simulator-round1-preview-failure-evidence.json` 区分文件生成、浏览器崩溃与 URL 策略失败。 |
| 经授权的 HTTP 预览续接 | 用户明确授权后，仅为该 scratch 目录启动临时 `127.0.0.1:3449` HTTP 服务，同一聊天的 `f10…` 实际打开 HTTP 页面并捕获完整截图。模型反复手工转存 base64，已通过 App 的精确停止入口停止该原回合，界面确认 Stop confirmed；没有重新创建聊天或重放原请求。 |
| 真实结果返回 | 父任务从该次已返回的浏览器工具结果中逐字节恢复 18,271 B JPEG，保存为 scratch 目录内 `browser-exact-preview.jpg`，未重绘或替换图像。SHA-256 为 `1b98b009e6e8d0ac4a13587f4d3b8f923ce37be400ba5fed998f4883dd75dec6`。同一聊天的 `1c930b97…` 只返回该既有文件，bridge 读回图片与浏览器原字节哈希相同；App 显示可打开的 Rendered browser screenshot。 |
| 底图批注与第二轮代码修改 | 在 App 预览实际截图后导入锁定底图，保留旧笔迹并新增下划线及指向 Continue 的笔迹。发送前核对固定版本 `canvas-eeb32df3-21cc-4875-baf2-992a953f99ba-r5.png`；第二轮 `f65f2030-cb2c-4116-b86d-7ad4e221d490` 一条文本加一张图，仍属于原 host/thread。原生历史中此 client ID 仅一条。真实 HTML 只将按钮 `#2563eb` 改为 `#16a34a`，回复完成；重新打开同一 HTTP 页面，实际渲染为绿色。 |

FEAT-001 的软件闭环已实际完成。证据在 `build/mini-simulator/`：`returned-browser-preview.jpg`、`round2-fixed-annotation.png`、`round2-annotation-sent.png`、`conversation-round2-current.json` 和 `round2-green-browser.jpg`。批注提交图 91,822 B，SHA-256 `a99c69eda9c0bdf5965179e8569eb2905a54921bb15b29687aff4802dd578607`；最终 HTML SHA-256 `ec1228d1329dcaa2859e046773848acf1e84e5a3d90db9bf218a4ddd1bcb9b98`。这份证据包含浏览器策略失败和模型转存失败后的人工恢复，不描述为首轮无干预成功；实际绘图输入来自 Simulator，未冒充实体 Pencil。

硬件 Pencil、掌面、硬件/浮动键盘、真实 VoiceOver，以及主 Mac 物理离线、实体 iPad 网络路径和用户手动在 Desktop UI 续接均未验证。远端审批、输入回答及未开放的远端控制能力也不因本机模拟器通过而视为可用。统一清单中的原故障条件继续由相应回归测试验证；没有对应运行证据的场景不标为完成。

## 提交与清理

App 的 63 个未发布提交归并为 28 个问题提交，FIX-028 位于最后；备份分支为 `backup/mini-app-before-grouping-20261016`，完整映射和冲突处理记录为 `build/mini-runtime/app-history-map.json`。归并前后文件树精确相同，均为 `2550542ba50eee633bcfc3f60c99db206e590875`；其后仅补充本报告等验收文档。MCP 的 17 个未发布提交归并为 11 个问题提交，备份及映射见运行报告。中间提交未逐个构建，不作各历史节点均独立通过的声明。

最终源码（包含 FIX-020）在严格 Swift 警告选项下完成生产 Simulator 双架构构建，日志为 `build/mini-final-source-build.log`。安装并重启后，原画布 r5 的完整存储字节与底图均保留；原草稿 ID、标题、正文和 JevCV 目的地可从统一入口找回，未提交新聊天。新增测试笔迹后通过文档菜单 Undo，笔迹与底图哈希恢复一致，文档 revision 为 7，而已提交的 r5 图片不变。证据为 `post-install-preservation.json`、`reference-relaunch-undo-verification.json` 和 `reference-relaunch-editable.png`。实际停止请求 `f10…` 的界面显示 Received by Codex，并单列 Response completion is not confirmed。

最终交付构建使用最终 HEAD 写入 `PetroglyphsSourceCommit`，日志为 `build/mini-delivery-build.log`；构建摘要和最终提交映射保存在 `build/mini-runtime/final-delivery.json`。文档更新后不重复未受影响的测试。

临时 `3437` bridge（PID 134）及 `3449` HTTP（PID 10494）均已停止，端口已关闭。原常驻 `3333` 仍为原 PID 96005，未替换、未重启，项目映射与设置未改。清理核对为 `build/mini-runtime/final-cleanup.json`。两个自动测试 iPad 已关机；人工验收 iPad 保留打开供查看，Device Hub 键盘捕获已关闭。没有 push、merge 或部署。
