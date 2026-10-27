# fcitx5 后端接口查证笔记

来源：fcitx5 master 源码（设备上运行为 5.1.23，该模块自 2017 年起接口未变）
关键文件：`src/ui/kimpanel/kimpanel.cpp`、`kimpanel.h`、`src/modules/dbus/dbusmodule.cpp`

## 一、kimpanel 是双向协议

### fcitx5 → 面板（调用面板对象的方法）

面板必须在 session bus 上注册服务名 `org.kde.impanel`，并在 `/org/kde/impanel`
路径上实现 `org.kde.impanel2` 接口。fcitx5 检测到这个服务名后，才把 kimpanel
模块置为 available（`Kimpanel::Kimpanel` 里 `watcher_.watchService("org.kde.impanel")`）。

| 方法 | 签名 | 说明 |
|---|---|---|
| `SetLookupTable` | `asasasbbii` | labels / texts / attrs / hasPrev / hasNext / cursor / layout。**候选词就靠这个** |
| `ShowLookupTable` | `b` | 候选栏显示/隐藏 |
| `UpdatePreeditText` | `ss` | preedit 串 + attrs |
| `UpdatePreeditCaret` | `i` | preedit 光标位置（UTF-8 字符数） |
| `UpdateAux` | `ss` | 辅助串（当 preedit 为空时用作提示） |
| `ShowPreedit` / `ShowAux` | `b` | |
| `RegisterProperties` | `as` | 输入法状态属性列表 |
| `UpdateProperty` / `RemoveProperty` | `s` | |
| `SetSpotRect` | `iiii` | 光标矩形 x,y,w,h —— **目前唯一可用的"聚焦了输入框"信号** |
| `SetRelativeSpotRect` | `iiii` | 同上，相对坐标 |
| `SetRelativeSpotRectV2` | `iiiii` | 同上 + scaleFactor |
| `UpdateSpotLocation` | `ii` | |
| `UpdateScreen` | `i` | |
| `ExecMenu` | `as` | 弹出菜单项 |
| `ExecDialog` | `s` | |
| `Enable` | `b` | 只在面板创建 / 切输入法时发 true，**不是焦点事件** |

fcitx5 在恢复时还会调面板的 `org.freedesktop.DBus.Introspectable.Introspect`，
用返回内容里有没有 `SetRelativeSpotRect(V2)` 决定用哪套坐标。

### 面板 → fcitx5（发到 `org.kde.kimpanel.inputmethod` 的 `/kimpanel`）

fcitx5 用 dbus match rule 捕获这些消息，不走普通方法分派：

| 方法 | 签名 | 说明 |
|---|---|---|
| `SelectCandidate` | `i` | 选中第 i 个候选（auxDown 非空时 i 要减 1） |
| `LookupTablePageUp` / `PageDown` | — | 翻页 |
| `TriggerProperty` | `s` | `/Fcitx/im` 弹输入法菜单；`/Fcitx/im/<imname>` 切换输入法（**带 30 秒延时定时器**）；`/Fcitx/<actionName>` 触发 UI 动作 |
| `PanelCreated` / `PanelCreated2` | — | 告知面板已就绪，触发 registerAllProperties |
| `ReloadConfig` / `Restart` / `Exit` / `Configure` | — | 控制 fcitx5 本体 |

**没有 `ProcessKeyEvent`。** 面板无法把字母键送进 fcitx5，按键必须走注入通道
（ydotool / uinput）。

## 二、UI 互斥

`Kimpanel::setAvailable()` → `userInterfaceManager().updateAvailability()`：
面板一上线，fcitx5 的输入面板 UI 就切到 kimpanel，**classicui 的候选窗随之不再显示**。
副作用：物理键盘打字时也没有 classicui 候选窗了，候选栏必须由我们的面板一直提供，
或者只在虚拟键盘打开时注册面板、关闭时注销（注销后 classicui 恢复）。

## 三、自动弹出没有官方通道

- `UserInterface` 上的 virtualkeyboard 显示能力只有 classicui 实现，kimpanel 不实现。
- dbusfrontend 有 `ShowVirtualKeyboard` / `HideVirtualKeyboard` /
  `VirtualKeyboardVisibilityChanged`（`src/frontend/dbusfrontend/dbusfrontend.cpp`），
  但那是给"客户端自己的输入上下文"用的，管不到桌面上的其他应用。
- 可用的近似信号：`SetSpotRect`。fcitx5 在 `InputContextFocusIn` 和
  `InputContextCursorRectChanged` 时都会推光标矩形，而 waylandim 只有在应用
  启用 text-input 时才有 input context，所以"收到 SetSpotRect"≈"聚焦了可输入控件"。
  误报来源：物理键盘打字时每次光标移动也会推。需要配合 evdev 观察物理键盘输入来抑制。

## 四、本地实测记录

- 注册 `org.kde.impanel` 后，`org.kde.kimpanel.inputmethod` 在数秒内从无到有，
  owner 变成 fcitx5（本机 classicui 环境实测）。说明自动切换成立。
- 面板进程退出后 fcitx5 会重新 releaseName，classicui 恢复（未细测闪烁）。
