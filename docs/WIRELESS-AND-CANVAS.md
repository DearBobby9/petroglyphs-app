# Wireless connection and canvas guide

当前真机验收状态及已知图片草稿停顿见 [进展与 TODO](PROGRESS-2026-10-17.md)。

## 中文使用步骤

1. 在 iPad 和 Mac 上连接同一个 Tailscale 网络。Mac 需要运行新版 Petroglyphs bridge。
2. 打开 App，在首页或 **Connection** 中选择发现的 Mac。点击 **Request wireless pairing**。
3. 首次连接时，核对 iPad 与 Mac 上的六位配对码。在 Mac 的批准页面点击 **Allow**。App 会保存这个 Mac，之后点击 **Connect** 即可切换，无需再次批准。无需插线或输入网址、端口。
4. 连接页显示 bridge Mac、连接状态、当前线路、地址及最近检查时间。**Local** 表示局域网线路，**Tailscale** 表示 tailnet 线路。App 优先使用局域网。
5. 打开工作区，选择 Codex 执行机器、项目和聊天。切回已使用的 Mac 时，App 恢复该 Mac 最近的聊天。首次使用的 Mac 需要选择聊天。每个 Mac 的聊天和草稿独立保存。
6. 使用 Apple Pencil 绘图。单指平移，双指缩放。**Canvas editing → Fit content** 回到内容，**Actual size** 恢复 100% 比例。App 重启后恢复画板位置。
7. 将画板快照加入聊天，输入文字，确认目标后发送一次。等待实际回复。打开回复中的图片，再点击 **Annotate**，可将它放回画板继续标注。

画板左上方的 **Select** 可进入对象选择模式：点击图片或笔迹，或拖框选中相交的对象；**Select all** 同时选中参考图片和所有笔迹。蓝框显示选区，点击 **Delete** 删除所选对象，**Undo** 可恢复。点击 **Done** 返回绘图和平移。删除结果会保存，撤销历史保留到 App 退出。**Clear ink** 只清笔迹；**Select export area** 只设置快照裁切范围。

输入区内容较长时，可滚动查看附件和文字。阅读图片回复时，收起键盘可增加可视区域。点击 **Latest / New messages** 跳到最新回复，再滚动到图片并打开。

发现列表只显示运行兼容 bridge 的 Mac。首次远程发现依赖安装时写入的 MagicDNS 发现入口；本机安装配置已由脚本生成。其他 Mac 也需要运行兼容 bridge，才会进入列表。开发版安装和 XCTest 仍受 Apple 的设备授权要求约束，这与 App 的无线配对是两个流程。

画板可持续向四个方向移动。为保证坐标精度，世界坐标设有 ±1,000,000 点的保护范围。快照加入消息后保持固定，后续绘图不会改变已加入的图片。

## Connect an iPad

1. Connect Tailscale on the iPad and Mac to the same tailnet.
2. Keep the updated Petroglyphs bridge running on each Mac you want to use.
3. Open Petroglyphs. Available Mac bridges appear on the landing page or under Connection.
4. For a new Mac, select it and choose **Request wireless pairing**.
5. Compare the six-digit code on the iPad with the approval window on that Mac.
6. If the codes match, choose **Allow** on the Mac.
7. Open the workspace. Select the Codex execution machine, project and chat.

After approval, the app saves that Mac. Select **Connect** to switch back without another approval. **Connected** identifies the active Mac. The app verifies the saved Mac identity before switching. A failed or cancelled switch keeps the previous connection.

Each Mac retains its own recent chat and drafts. Switching back restores the most recent chat saved under that exact bridge URL. A new Mac starts without a selected chat.

Pairing does not require a cable or manual address entry. Tailscale access rules must allow the iPad to reach the Mac bridge. A Mac without a running, compatible bridge does not appear as an available bridge.

The connection page shows the bridge Mac, connection state, active route, active address and last successful check. **Local** means the iPad reaches the bridge through the local network. **Tailscale** means it uses the Mac's tailnet address. The bridge prefers the local network and retains verified Tailscale addresses for recovery. Disconnecting Tailscale prevents the fallback from working outside the local network.

The Codex execution machine is a separate selection. The bridge can reach a chat on **This Mac** or through a configured Codex Remote Connection. Changing the network route does not change that chat's destination.

Pairing approval expires after five minutes. Reject or cancel unexpected requests. The bridge encrypts paired credentials with a temporary P256/HKDF/AES-GCM session. It preserves the existing bridge identity and token. Re-pairing the same Mac preserves its saved conversation key.

## Installation discovery setup

Tailscale does not expose its peer inventory directly to this iPad app. The installer supplies a token-free MagicDNS discovery entry and a tailnet-specific network configuration. That Mac's bridge queries the local Tailscale inventory and probes online macOS peers for compatible bridges. Verified peers use their MagicDNS names, so adding another compatible Mac does not require entering its IP address on the iPad. Bonjour provides discovery on the local network. The app also remembers discovered tailnet bridge addresses for later searches.

Generate an installation-specific plist on the Mac while Tailscale is connected:

```sh
python3 scripts/configure-discovery.py --output build/wireless/Info.plist
```

Build the app with `INFOPLIST_FILE` pointing to that generated file. It contains discovery origins and an HTTP exception scoped to this tailnet's MagicDNS domain, not a pairing token or Tailscale administrator credential. The tracked source plist contains no personal tailnet addresses. A build made without this setup still discovers nearby bridges through Bonjour, but a fresh installation cannot discover a distant tailnet without an entry. Regenerate the installation configuration if its seed Mac is removed from the tailnet.

This setup concerns app communication and pairing. Installing a development build and running XCTest still use Apple's provisioning and device automation requirements. App Store or TestFlight distribution is a separate installation workflow.

## Send a drawing and continue the conversation

Select the destination chat before sending. Draw or import an image, then add the canvas snapshot to the chat. Add text and send the complete message once. A queued receipt establishes acceptance; wait for the reply to establish execution. Open a returned image and choose **Annotate** to use it as the canvas reference image.

An uncertain send is not automatically replayed. Keep the existing receipt and check its status. Stop targets the active turn reported by the selected execution host.

## Canvas navigation

Choose the visible **Select** control to tap an image or stroke, or drag a box across the objects to select. **Select all** includes both the reference image and ink. A blue outline marks the selection. **Delete** removes selected objects; **Undo** restores them. Choose **Done** to return to drawing and navigation. Deletions persist across relaunch; undo history lasts for the current app session. **Clear ink** affects ink only, and **Select export area** sets the snapshot crop.

Use one finger to pan in any direction and two fingers to pinch between 25% and 400%. Open **Canvas editing** for **Fit content**, **Actual size**, **Zoom in** and **Zoom out**. The app restores the viewport after relaunch.

The canvas uses stable document coordinates and a recentering scroll window. Navigation does not move saved ink or change a saved export region. It has a precision guard at ±1,000,000 document points. Reaching that guard shows a message and a **Fit content** action. This is a finite numeric limit, rather than the old viewport edge.

The Pencil draws on the physical iPad. Finger gestures navigate the canvas. The Simulator permits finger or mouse drawing for test coverage. A canvas snapshot is fixed when attached to a message; later drawing does not alter that attachment.
