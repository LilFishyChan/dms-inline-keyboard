# Inline Keyboard 架构与功能清单

触摸键盘插件（DMS plugin），键盘本体自己画，输入法能力全部来自 fcitx5。

---

## 一、功能清单

### 键盘本体

| 功能 | 说明 |
|---|---|
| 全键位布局 | 数字行 + QWERTY + 标点 + 退格/回车，共 5 行 |
| 修饰键 | Shift / Ctrl / Alt / Win / Fn，三态（一次 / 锁定 / 按住），四种模式 |
| 长按符号 | 数字行与标点行长按输出上档字符 |
| Esc 对调 | 可选把 Esc 和 `` ` `` 换位 |
| 页面切换 | 数字行 ↔ 功能键行 ↔ 表情页（表情页未实现，占位） |
| 窗口形态 | 停靠（底部独占区）/ 浮动（可拖动）两种，共用同一套卡片 |
| 外观 | 缩放 50%–150%、背景/按键透明度独立可调 |
| 防误触 | 物理键盘一按，虚拟键盘自动收起（可关） |
| 窗口避让 | 停靠模式下占合成器 exclusive zone，不遮挡应用内容 |

### 候选词

| 功能 | 说明 |
|---|---|
| 顶栏候选 | 显示当前页候选，最多 18 个（前三页），无数字序号 |
| 点击选词 | 直接点候选上屏，不依赖输入法数字键 |
| 展开列表 | 点 `⌄` 后键区整块换成候选网格（5 行），右侧一列按钮：`↑` 上翻 / `↓` 下翻 / 空 / `⌫` 退格 / `↵` 回车 |
| 全量候选 | 展开时通过 `BulkCandidateList::candidateFromAll()` 一次取完，不翻页 |
| 预编辑 | 显示拼音串（wayland 下取 clientPreedit） |

### 输入法控制

| 功能 | 说明 |
|---|---|
| 空格键标识 | 显示子模式标签：rime 中文 `万`、英文 `abc`、键盘布局 `en` |
| 地球键单击 | 在「输入法 + 子模式」平铺列表里循环下一项 |
| 地球键长按 | 弹出输入法列表（带图标、当前项高亮） |
| 图标解析 | 从 icon theme 解析成绝对路径给 QML |

### 快捷栏 / 动作

| 功能 | 说明 |
|---|---|
| 动作类型 | 内置动作 / `dms ipc` 调用 / 合成器命令 / 任意命令 |
| 拖动排序 | 编辑态拖拽重排，落点计算与预览同源 |
| 槽位 | 右上角可放一个常用动作 |
| 图标选择 | 动作可配图标，带选择器 |

### 设置项（11 项）

`scale`（缩放）、`bgOpacity`、`keyOpacity`、`defaultFloating`（默认浮动）、
`escSwap`、`closeOnPhysicalInput`（物理键收起）、`avoidWindows`、
`modifierMode`（修饰键模式）、`actions`（动作表）、`quickBarActions`、`slotActionId`

---

## 二、与 fcitx5 的通信

实时数据走一条 **Unix socket**（私有行协议），低频命令走 `$XDG_RUNTIME_DIR/inlineKeyboard-*` 文件。
**没有任何轮询**：状态和输入法清单都是 addon 主动推。

### 通道清单

**主通道：Unix socket（实时）**

`$XDG_RUNTIME_DIR/inline-keyboard.sock`，`addon` 是服务端，`QML` 用 `Quickshell.Io/Socket` 连。

| 消息 | 方向 | 内容 |
|---|---|---|
| `key:<keysym>[:<mods>]` | QML → addon | 按键直通，转成 `VirtualKeyboardEvent` |
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

**socket 的两个坑**（都实测踩过）：

1. `DataStream` 不设 `parser` 时**永远不会**触发 `read` 信号——连上了也收不到一个字节
2. `SplitParser` 已经把一行切好，回调里不能再找 `\n`，否则整条消息被丢弃

### 非文件通道

| 用途 | 方法 |
|---|---|
| 按键注入 | **ydotool**（真实 `/dev/uinput` 设备，经 libinput → 合成器 → 应用，合成器快捷键也生效） |
| 切换输入法 | **addon `im:<name>` 指令**。`fcitx5-remote -s` 只作用于最后获得焦点的 context，键盘窗口一出现就失效，所以改由 addon 在进程内 `setCurrentInputMethod()` |
| 中英文切换 | **ydotool 发真实 Shift**（rime 默认绑定）。kimpanel 的 `TriggerProperty("/Fcitx/im")` 查源码是弹菜单，不能切中英 |
| 输入法清单 | **addon 直接读 `InputMethodGroup::inputMethodList()`**（D-Bus 侧的 `FullInputMethodGroupInfo` 只作早期实验，已不用） |

---

## 三、实现方法

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

**为什么是 addon 而不是 D-Bus / kimpanel**

候选只存在于 fcitx5 进程内的 `InputContext::inputPanel().candidateList()`。
D-Bus 侧全部查过：`Controller1` 只有输入法管理、`/virtualkeyboard` 只有显隐、
`/rime` 只有 schema、kimpanel 面板只给当前页、fcitx5 的 dbus 模块源码里
`grep Candidate` 是空。所以**只能进程内**。

kimpanel 协议试过也能跑（接管 UI、收预编辑/属性信号），但它只推当前页，
且翻页在 rime 上无效（rime 的候选列表是 `BulkCandidateList`，
`toPageable()->next()` 不起作用），拿不到全量。所以最终回到 addon。

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

### 已踩过的坑（改代码前必读）

| 坑 | 现象 | 正确做法 |
|---|---|---|
| 不继承 `VirtualKeyboardUserInterface` | fcitx5 SIGSEGV | 必须继承（`updateVirtualKeyboardVisibility()` 无条件 static_cast） |
| `available()` 返回 false | addon 被立刻卸载 | 恒返回 true，用 `setInputMethodMode` 控制 |
| 构造期调 `updateAvailability()` | fcitx5 崩溃 | 延迟到事件循环里 |
| `Library=` 写相对名 | `Could not locate library` | 写绝对路径，不带 `.so` |
| 工厂宏用 V2 | `undefined symbol: fcitx_addon_factory_instance` | 用 `FCITX_ADDON_FACTORY_V2_BACKWARDS` |
| `std::filesystem::exists()` | 抛异常打崩进程 | 用 `::access()` |
| `candidate()` 拷贝 | `CandidateWord` 是抽象类，编译失败 | 用 `const auto &` |
| `totalSize()` 当上限 | 只拿到当前页（rime 懒加载） | 循环 `candidateFromAll` 到抛异常 |
| `label`/`icon` 用当前 ic | 切换后还是旧标签 | 挑输入法与全局一致的那个 context |
| `dump()` 用传入的 ic | `InputContext::property` 段错误 | 忽略传入值，自己扫 context |
| QML 里用 `{...x}` | `Unexpected token '...'` | 显式复制字段（`data.js` 的 `cloneIm`） |
| `FileView` 读运行时文件 | `text` 恒空 | `Process` + `StdioCollector` |
| `anchors.fill` 在 `Column` 里 | 布局失效 | 放 card 直接子层级 + 显式 y/height |
| `visible: false` 的项在 `Column` 里 | 后续元素位置上移 | 用 `opacity` 或预先算好坐标 |

---

## 四、测试

| 层 | 方法 | 命令 |
|---|---|---|
| 数据映射 | 纯函数单测（JS 131 个） | `node --test tests/` |
| keysym 映射 | C++ 单测（17 项） | `ctest --test-dir fcitx5-addon/build` |
| 数据链路 | 端到端自检（不启动 UI） | `./scripts/probe.sh` |
| 全量候选 | 同上，加 `all` 参数 | `./scripts/probe.sh all` |
| UI | 手动 + IPC 调试接口 | `dms ipc call inlineKeyboard debugRows` 等 |

`probe.sh` 会依次检查：fcitx5 在跑 / addon 已加载 / 键盘标志 / UI 是否接管 /
状态字段是否完整。数据层对了再查 QML，能省掉一半排查时间。
