# Inline Keyboard 架构与功能清单

**简体中文** · [English](ARCHITECTURE.md)

触摸键盘插件（DMS plugin），键盘本体自己画，输入法能力全部来自 fcitx5。

---

## 一、与 fcitx5 的通信

实时数据走一条 **Unix socket**（私有行协议），低频命令走 `$XDG_RUNTIME_DIR/inlineKeyboard-*` 文件。
**没有任何轮询**：状态和输入法清单都是 addon 主动推。

### 通道清单

**主通道：Unix socket（实时）**

`$XDG_RUNTIME_DIR/inline-keyboard.sock`，`addon` 是服务端，`QML` 用 `Quickshell.Io/Socket` 连。

| 消息 | 方向 | 内容 |
|---|---|---|
| `key:<keysym>[:<mods>]` | QML → addon | 按键直通，转成 `VirtualKeyboardEvent` |
| `text:<utf8>` | QML → addon | 表情 / 符号上屏：addon 直接 `InputContext::commitString()`，多码位表情只能走这条 |
| `state:{json}` | addon → QML | 面板状态推送（内容不变不推） |
| `imlist:{json}` | addon → QML | 输入法清单；键盘打开时推，新客户端连上也补推一次 |

延迟：发送 **0.0014ms**，端到端（按键 → fcitx5 处理 → 状态回到 QML）**约 2.2ms**。
对比 ydotool 的 **25ms**。

**路由规则**（`injectKey` 里判断）：

```
直通 (socket):  !fcitxImKeyboard 且 无 Ctrl/Alt/Super 组合
ydotool:        纯键盘布局（keyboard-us），或带修饰键的组合
```

- 纯键盘布局下 fcitx5 的 `inputMethodEngine()` 返回 null，虚键盘事件被丢弃（实测按键上不了屏）
- 带修饰键的组合必须让合成器看到（Alt+Tab、Mod+数字），socket 到不了合成器

**辅助通道：文件（缓冲区 / 自检用）**

| 文件 | 方向 | 谁写 | 谁读 | 内容 |
|---|---|---|---|---|
| `inline-keyboard-active` | 插件 → addon | daemon | addon | 键盘是否打开（文件存在 = 打开）。驱动 UI 接管/释放 |
| `inline-keyboard-status.json` | addon → 测试工具 | addon | `probe.sh` | 面板状态快照（和推送内容相同，留给自检用，QML 不再读它） |
| `inline-keyboard-imlist.json` | addon → 测试工具 | addon | `probe.sh` | 输入法清单快照（QML 走 socket 推送，不再读它） |
| `inline-keyboard-allcand.json` | addon → 插件 | addon | `FcitxBridge` | 全量候选数组（socket 没连上时的兜底） |
| `inline-keyboard-expand` | 插件 → addon | `FcitxBridge` | addon | 请求全量候选（写 `1`，addon 读完删除） |
| `inline-keyboard-select` | 插件 → addon | `FcitxBridge` | addon | 选第 N 个候选（写索引，addon 读完删除） |
| `inline-keyboard-physical-input` | addon → 插件 | addon | daemon | 物理键盘按下的标记（读完删除，用于收起键盘） |

### 传输方式

- **socket**：`SplitParser` 按 `\n` 切，一方发一行；addon 侧非阻塞写，`EAGAIN` 时丢弃等下一轮
- **文件**（只剩 expand / select / physical-input / keyboard-active 四个低频命令）：
  `tmp` + `rename` 原子写；addon 轮询读到就 `unlink`

**socket 的两个约束：**

1. `DataStream` 不设 `parser` 时**永远不会**触发 `read` 信号——连上了也收不到一个字节
2. `SplitParser` 已经把一行切好，回调里不能再找 `\n`，否则整条消息被丢弃

### 非文件通道

| 用途 | 方法 |
|---|---|
| 按键注入 | **ydotool**（真实 `/dev/uinput` 设备，经 libinput → 合成器 → 应用，合成器快捷键也生效） |
| 切换输入法 | **addon `im:<name>` 指令**。`fcitx5-remote -s` 只作用于最后获得焦点的 context，键盘窗口一出现就失效，所以改由 addon 在进程内 `setCurrentInputMethod()` |
| 中英文切换 | **rime 自己的 D-Bus `SetAsciiMode`**（`busctl --user call org.fcitx.Fcitx5 /rime org.fcitx.Fcitx.Rime1 SetAsciiMode b …`）。用 ydotool 发 Shift 不行 —— 键盘窗口持焦点时按键落不到输入框 |
| 输入法清单 | **addon 直接读 `InputMethodGroup::inputMethodList()`**（D-Bus 侧的 `FullInputMethodGroupInfo` 只作早期实验，已不用） |

---

## 二、实现方法

### 三层结构

```
┌─ fcitx5 进程 ────────────────────────────┐
│  inline-keyboard-status addon (C++ / UI 类型)     │
│  · 键盘打开时才被当成有效 UI（UIType=OnScreenKeyboard）│
│  · 轮询 40ms/200ms/5s 自适应，dump 面板状态 │
│  · 全量候选用 BulkCandidateList 一次取完    │
│  · 监听物理键事件写标记                     │
└───────────────┬──────────────────────────┘
                │ 7 个文件（见上表）
┌───────────────▼──── DMS 插件进程 ────────┐
│  FcitxBridge.qml（240 行）                │
│  · socket 收发、状态解析、候选、输入法清单   │
│  · 唯一的 fcitx5 通信层                     │
├──────────────────────────────────────────┤
│  KeyRouter.qml（256 行）                  │
│  · 修饰键三态状态机                         │
│  · 按键路由：直通 fcitx5 还是 ydotool       │
├──────────────────────────────────────────┤
│  InlineKeyboardDaemon.qml（846 行）             │
│  · 窗口生命周期 / IPC / 设置读写             │
│  · alias 转发上面两个组件的属性              │
├──────────────────────────────────────────┤
│  data.js（213 行，纯函数 + 131 个单测）      │
│  · JSON → 键盘内部模型                      │
│  · parseStatus / buildImRows / nextImRow   │
├──────────────────────────────────────────┤
│  QML 组件                                 │
│  KeyboardCard / CandidateBar / QuickBar   │
│  BottomBar / ImPicker / Key / Ripple …    │
└──────────────────────────────────────────┘
```

### 关键设计决定

**为什么是 addon —— 候选只存在于进程内**

候选只存在于 fcitx5 进程内的 `InputContext::inputPanel().candidateList()`。
D-Bus 侧全部查过：`Controller1` 只有输入法管理、`/virtualkeyboard` 只有显隐、
`/rime` 只有 schema、fcitx5 的 dbus 模块源码里 `grep Candidate` 是空。
所以**只能进程内**。

**UI 接管与释放**

addon 声明 `UIType=OnScreenKeyboard` + `UIPriority=50`。键盘打开时：
1. 插件写 `inline-keyboard-active`
2. addon 轮询到 → `setInputMethodMode(OnScreenKeyboard)`
3. 延迟 50ms 调 `updateAvailability()` → fcitx5 重选 UI → 选到 addon（优先级高）
4. classicui 被 `suspend()`，候选窗让位

收起时反向操作，`updateAvailability()` 选回 classicui。

**为什么按键不走 addon**

`KeyEvent` 注入虽然可行（`KeyState::Virtual` 标记 fcitx5 内部不检查），但那样
按键只在 fcitx5 内部流转，合成器快捷键（Alt+Tab、Mod+数字）不生效。
ydotool 是真实设备，行为与物理键盘完全一致。

**窗口层**

界面是 `keyboardFocus: None` 的 layer-shell `PanelWindow`，所以注入的按键落在获得焦点的应用
上，永远不会落到键盘自己身上。停靠模式把窗口尺寸设成「键盘 + 拼音预留」并设置
`exclusiveZone`，其它窗口会被顶上去；浮动模式显式退出（`exclusionMode: Ignore`），所以能拖到
状态栏上面。

