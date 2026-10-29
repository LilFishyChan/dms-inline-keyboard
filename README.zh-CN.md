# Inline Keyboard —— 给 DankMaterialShell 的触摸键盘

**简体中文** · [English](README.md)

![Inline Keyboard 停靠状态，拼音输入时候选词直接画在键盘里](docs/images/keyboard.png)

一个 DMS 插件：像手机输入法（Gboard 那种）的屏幕键盘，**输入后端是 fcitx5**。候选词、拼音
串、当前输入法通过一条 Unix socket 从自写的 fcitx5 addon 取回，直接画在键盘内部，中文输入
不再需要另开一个候选窗。

> 状态：功能完整，已在两台设备上日常使用（一台主机，一台跑 Arch Linux ARM 的小米平板 5）。
> 下面这些都能端到端跑通：`ydotool` 按键注入、键盘内候选、候选列表页、两页键位 + Fn 层、
> 可拖拽排序的动作格、停靠与浮动两种形态（位置可拖）、透明度面板、缩画面板、表情/符号页、
> 最小化成气泡、语音模式、多语言字符串。
>
> 实际在硬件上验证过什么，见 [实际验证](#实际验证)；这个项目是怎么做出来的，见
> [AI 参与](#ai-参与)。

## 功能

**输入**

- 手机式布局：两页键位加一个 Fn 层（F1–F12、小键盘、方向键、编辑键）
- 候选词、拼音串和输入法状态都画在键盘**内部** —— 没有独立候选窗；拼音过长时从前面省略
- 可翻页、可滚动的候选列表；剪贴板动作；地球键循环切换输入法，并显示当前子模式标识
  （万 / abc）
- 表情页（9 个分类、约 1900 个表情）和符号页（数学、标点、箭头、货币、几何、框线……）

**布局与外观**

- 停靠（贴底、占用屏幕空间）或浮动（可拖到任意位置）
- 拖动把手移动，拖动边缘缩放 —— 尺寸会被记住
- 面板与按键分别可调透明度；长按重复间隔可调
- 特殊键可显示为图标 / 简写 / 全称；Win 键可以配自定义图标
- 最小化成一个小浮动气泡（位置会被记住）；语音模式把键盘收成一条胶囊
- 颜色完全跟随当前 DMS 主题

**动作**

- 功能页内置 11 个动作（撤销、重做、设置、浮动、尺寸、透明度、下一个输入法、剪贴板、
  窗口避让、语音、最小化），另可添加自定义 `sh -c` 命令
- 拖动排序；可以把动作拖进快捷栏或右上角圆槽
- Shift / Ctrl / Alt / Win 四种点击行为

**集成**

- IPC 接口（`toggle`、`open`、`close`、`setMode`、`setPage`……）与可选的 DankBar 小部件
- 默认英文，自带 `zh_CN` 翻译

| 第二页键位（Fn 层） | 表情与符号 |
|---|---|
| ![第二页：Esc/PrtSc、F1–F12、编辑键、小键盘](docs/images/page2.png) | ![带分类条的表情/符号页](docs/images/emoji.png) |

## 设计

按键通过 **`ydotool`** 发出——它写的是真实 `uinput` 设备，在合成器眼里就是一把物理键盘，
所以修饰键、Alt+Tab、Mod+数字、`Print` 全是原生行为。当前输入法有引擎、且没有按住
Ctrl/Alt/Super 时，按键改为**直接短路进 fcitx5**。候选、拼音串和输入法状态来自一个自写的
fcitx5 addon（[独立仓库](https://github.com/LilFishyChan/fcitx5-inline-keyboard-status)），
经 Unix socket **推送**过来，没有轮询。

```text
 key press ──ydotool──▶ compositor ──▶ focused app ──text-input──▶ fcitx5
                                                                     │
                                                        fcitx5 addon │
                                                     (inline-keyboard-status)
                                                                     │
 keyboard surface (QML)  ◀────────state / candidates─── Unix socket ──┘
                │
                └── key / select / commit ──▶ addon ──▶ fcitx5
```

协议表、窗口层与设计决定：`docs/ARCHITECTURE.zh-CN.md`。
几何与布局规则：`docs/layout.zh-CN.md`。

## 依赖

**必需**

- `ydotool`，并且 `ydotoold` 在跑：
  ```sh
  systemctl --user enable --now ydotool    # ydotool 包自带的单元
  ```
  `ydotool` 通过 `/dev/uinput` 写入，在合成器眼里就是一把真实键盘。所以打字、修饰键、
  合成器快捷键（Alt+Tab、Mod+数字、`Print`）全是原生行为 —— 没有虚拟键盘协议，也不用查
  键位绑定表。
- DMS ≥ 2.0（`~/.config/dms/plugins/`；1.6.x 用的是
  `~/.config/DankMaterialShell/plugins/`）

`StartupCheck.qml` 只探测 `ydotool` —— 这是唯一一个没有它就一个字都打不出来的东西。下面
其余依赖缺失时都是降级，不会直接坏掉。

**强烈推荐**（没有它们，按键、快捷栏和设置照样能用，只是没有候选、也不能切输入法）

- `fcitx5`，且有一个启用的输入法（拼音 / rime）
- **`inline-keyboard-status` fcitx5 addon** —— 键盘只能通过它拿到候选和输入法状态。不装的话候选栏
  一直是空的，地球键也切不了上下文：
  ```sh
  # addon 在独立仓库里，不会随插件一起 clone 下来
  git clone https://github.com/LilFishyChan/fcitx5-inline-keyboard-status /tmp/fcitx5-inline-keyboard-status
  cd /tmp/fcitx5-inline-keyboard-status && cmake -B build -G Ninja && ninja -C build
  cmake --install build --prefix ~/.local      # 库文件和 addon conf 一次装齐
  systemctl --user restart 'app-org.fcitx.Fcitx5@autostart.service'
  ```

**可选**

- `vinput` —— 语音输入。没有它，「语音输入」动作和语音模式是灰的，键盘其余部分不受影响。

剪贴板复制走 DMS 自带的 `dms cl copy`，不需要额外装什么。

## 安装

```sh
git clone https://github.com/LilFishyChan/dms-inline-keyboard ~/.config/dms/plugins/inlineKeyboard
systemctl --user restart dms       # 首次安装必须重启
dms ipc call plugins status inlineKeyboard
dms ipc call inlineKeyboard toggle
```

clone 出来的目录名必须等于插件 id（`inlineKeyboard`）。

## 源码结构

| 文件 | 职责 |
|---|---|
| `plugin.json` | 清单：id、权限、依赖、`startupCheck` |
| `StartupCheck.qml` | 启用前只探测唯一的硬依赖 `ydotool` |
| `InlineKeyboardDaemon.qml` | 常驻守卫：状态、设置、IPC 命令、两个窗口的宿主 |
| `KeyboardWindow.qml` | 停靠形态（layer-shell 锚定）键盘窗口 |
| `FloatingKeyboardWindow.qml` | 浮动键盘窗口，可拖动，自动夹在屏幕内 |
| `KeyboardMetrics.qml` | 卡片宽 / 单位宽 / 键高 / 把手高的**唯一**计算源 |
| `KeyboardCard.qml` | 卡片外壳：共享状态、拖拽状态机、翻页、整体拼装 |
| `QuickBar.qml` | 顶部快捷栏：导航钮、快捷动作、右侧圆槽 |
| `ActionList.qml` | 功能动作网格、编辑态、拖拽排序 |
| `CandidateBar.qml` | 候选条 —— 第一个词从左边省略，其余从右边省略 |
| `TransparencyPanel.qml`、`OpacitySliderRow.qml` | 双滑块透明度面板 |
| `ImPicker.qml` | 长按地球键弹出的输入法选择器 |
| `DragGhost.qml` | 拖动动作时跟手的方块 |
| `BottomBar.qml` | 底部把手行：收起、输入法、fcitx5 托盘图标 |
| `EmojiPanel.qml` | 表情 / 符号网格 + 底行（返回 / 表情·符号 / 退格） |
| `EmojiCategoryBar.qml` | 表情页顶部那行分类条 |
| `Key.qml` | 单个按键：双行键帽、Fn 层替换、涟漪 |
| `ActionIcon.qml` | 单个动作图标 —— 列表 / 快捷栏 / 圆槽 / 拖拽块共用 |
| `Ripple.qml`、`Slider.qml` | 按键、按钮和透明度面板用的小控件 |
| `InlineKeyboardWidget.qml` | 可选的 DankBar 药丸，切换同一个全局「打开」变量 |
| `actions.js` | **纯函数**动作表逻辑（清洗、移动、过滤、命中测试），有单测 |
| `layouts/phone.js` | 布局数据：行、单位、键位表、功能键页 |
| `layouts/emoji.js` | **生成物**：表情分组（Unicode 16）+ 符号分组 |
| `tools/gen-emoji.py` | 从 Unicode 的 `emoji-test.txt` 重新生成 `layouts/emoji.js` |
| `scripts/` | 早期留下的辅助脚本，给托盘图标和输入法清单兜底用 |
| `translations/` | 各语言字符串（`zh_CN.json`）；源串始终是英文 |
| `icons/` | 手绘 SVG（「浮动」图标） |
| `docs/` | 协议笔记与布局/几何规则；中文版是 `*.zh-CN.md` |

## 开发

```sh
node --test tests/        # 纯逻辑单测：actions.js
qmlformat *.qml >/dev/null  # 语法解析检查；Arch 上的 qmllint 是个空壳
                            # （语法写错它也返回 0，别信它）

# 部署到本机和平板，然后重启 DMS
rsync -a --exclude=.git --exclude=docs --exclude=tests ./ \
      ~/.config/dms/plugins/inlineKeyboard/
rm -rf ~/.cache/quickshell/qmlcache          # QML 磁盘缓存必须清
systemctl --user restart dms
dms ipc call plugins status inlineKeyboard         # 期望：loaded
```

QML 按路径缓存编译产物 —— 改完 `.qml` 一定先清 `~/.cache/quickshell/qmlcache`，否则调试的是
已经不存在的行号。嵌套组件内部的改动有时能靠 `plugins reload` 生效，但可靠做法是完整
`systemctl --user restart dms`。

### IPC

| 命令 | 作用 |
|---|---|
| `dms ipc call inlineKeyboard open` / `close` / `toggle` | 显示 / 隐藏 / 切换键盘 |
| `dms ipc call inlineKeyboard toggleFloat` | 停靠 ↔ 浮动 |
| `dms ipc call inlineKeyboard setPage <page1\|page2\|emoji>` | 切换键页 |

## 表情与符号

第一页底行的表情键打开表情页。它和键区在同一个卡片里（同高、同样的上下栏），靠
`page: "emoji"` 切换，而不是 `mode`。

- **顶栏** —— 分类条：`全部` 加九个 Unicode 分类（表情侧），以及八个符号分类（数学、标点、
  箭头、货币、几何、框线、序号、杂项）。放不下时横向滚动。
- **中间** —— 可滚动的网格，四行高，列数随卡片宽度变。
- **底行** —— `返回`、`表情 | 符号` 分段开关、退格（按住可重复）。

插入**不**走按键注入通道。`EmojiPanel` 只报告字符，由 daemon 交给 fcitx5 addon，addon 在
进程内调 `InputContext::commitString()`。ZWJ 表情（`👨‍👩‍👧`）由多个码位组成，没法表示成
keycode，所以这是唯一可行的路径。没装 addon 时字符改为复制到剪贴板（走 DMS 自带的
`dms cl copy`）。

`layouts/emoji.js` 是**生成物**：`python3 tools/gen-emoji.py` 读取 Unicode 16 的
`emoji-test.txt`（缓存在 `tools/.cache/`），写出 1900 个表情（肤色变体是有意排除的）以及
符号表。生成结果本身提交进仓库，所以用户运行时不需要 Python。

## 编辑态

在动作页底部点铅笔进入编辑态。此时快捷栏和动作列表显示的是**松手之后的样子**，而不是当前
状态：

| 拖到哪 | 拖动时看到 | 松手结果 |
|---|---|---|
| 两个快捷栏项之间 | 该项占住这个位置，其余让位 | 插入到这个索引 |
| 快捷栏最左 / 最右外侧 | 同上，索引 0 / 末尾 | 插到边缘 |
| 快捷栏已满 | 末尾那项变成幽灵块出现在**列表顶部** | 末尾项被挤回列表 |
| 右侧圆槽 | 槽里显示拖来的图标 | 拖来的动作占槽，原来的回列表 |
| 拖回列表 | 列表在落点处裂开一个空位 | 从快捷栏移出 |

快捷栏落点由跟手块的中心算（`Actions.quickBarInsertIndex`），最终数组由
`Actions.planQuickBarDrop` 生成 —— 和真正落盘调用的是同一个函数，所以预览不可能和结果
不一致。容量是 `min(6, floor((midW + gap) / (slotW + gap)))`，随键盘宽度变；满了就把
**末尾**那项挤出去腾位置。

幽灵块（插进快捷栏的那项、被挤回列表的那项）用 55% 不透明度 + 2px `primary` 描边。被拖动
的那块在快捷栏上方**不淡化** —— 幽灵已经表达了预览，两个都半透明就看不清拖的是什么了。

快捷栏的项是胶囊形，编辑态背景是 `surfaceContainerLow` 的胶囊，`primary` 边框跟着项走：
没有项就不画；有项时从第一个项左侧一个间距，画到最后一个项右侧一个间距。

## 修饰键行为

`Shift` / `Ctrl` / `Alt` / `Win` 有三种状态：`0` 关闭、`1` 激活（按下一个普通键即清除）、
`2` 锁定（只有再点本键才清除）。触摸如何在三者间切换是插件设置（`modifierMode`）：

| 设置 | 触摸 | 按下普通键时 |
|---|---|---|
| `noLock` —— 按住才生效 | 按下 → `1`，松手 → `0`；点一下不留状态 | —— |
| `toggle` —— 点一下激活 | 点一下 `0` ⇄ `1` | 清除 |
| `tapLock` —— 点一下锁定 | 点一下 `0` ⇄ `2` | 保留锁定 |
| `doubleTapLock`（默认） | 点 → `1`；300ms 内再点同键 → `2`；点 `2` → `0` | 清 `1`，保留 `2` |

所以 `doubleTapLock` 就是「单击等于 `toggle`、双击等于 `tapLock`」。`Caps Lock` 不受这个
设置影响 —— 它永远是普通开关，普通键也不会清它。按下/松开事件只为 `noLock` 接线；其它模式
都按「点击」处理。切换模式会清空所有修饰键状态。

## 颜色

一切都是 DMS 动态主题（`Theme.*`）来的，插件里没有一个硬编码颜色。表面遵循 M3 的 surface
阶梯，所以切换明暗主题或换壁纸会自动跟上：

| 部位 | Token |
|---|---|
| 卡片背景 | `Theme.surface` —— 和设置页同一个值 |
| 键面（普通） | `Theme.surfaceContainer` |
| 键面（修饰键：Tab / Ctrl / Shift…） | `Theme.surfaceContainerHighest` |
| 键面（Fn 层） | `Theme.primary` @ 0.16 |
| 键面（激活、未锁定） | 底色不变；2px `primary` 描边 + `primary` 文字 |
| 键面（锁定修饰键、当前页） | `Theme.primary` 实心，字形 `Theme.onPrimary` |
| 键帽文字 / 图标 | `Theme.surfaceText`（= `onSurface`） |
| 上档符号行 | `Theme.onSurfaceVariant` |
| 动作磁贴（默认 / 激活） | `Theme.surfaceContainer` / `Theme.primary` 实心 + `onPrimary` |
| 圆钮 | `Theme.surfaceContainerHigh` |
| 涟漪、拖拽块、落点预览 | `Theme.primary` @ 0.06–0.92 |
| 卡片与选择器描边 | `Theme.outlineVariant` @ 0.7 |

按键和动作磁贴在正常状态下**没有边框**。激活态不用 `Theme.primaryContainer`：DMS 会给容器
色叠一层 elevation 淡化，浅色主题下出来是 `#ffd2d4`，和键面 `#ffd1dd` 几乎一样，等于没有
反馈。所以三个层级靠**填充 / 描边 / 实心**的形状差异区分 —— `surfaceContainer` 填充 →
`primary` 2px 描边 → `primary` 实心 —— 这在两种主题下都成立，而 alpha 叠加不成立。

## 翻译

源串是英文，统一走 `I18n.trFor("inlineKeyboard", …)`（卡片、设置页、启动检查里各有一个 `tr()`
辅助函数）。译文放在 `translations/<locale>.json`：

```json
{ "Inline Keyboard": { "Appearance": "外观" } }
```

译文由 `PluginService` **在插件 QML 构造之后异步**注册，而且只在 `I18n.onLocaleApplied`
时（即 DMS 启动时）生效：

- 加/改译文后要重启 shell —— `dms ipc call plugins reload` 不会重新加载译文。
- 绑定里直接写 `I18n.trFor(...)` 只求值一次，那时表还是空的，之后永远停在英文。
  `KeyboardCard.qml` 和 `InlineKeyboardSettings.qml` 里的 `tr()` 因此读一个 `localeVersion`
  属性，由短定时器在表里出现 `inlineKeyboard` 时翻转 —— 这个属性变化才让绑定重算。
  （在插件内部 `Connections { target: I18n; function onPluginTranslationsChanged() … }`
  不会触发 —— 得轮询。）
- `trFor` 的第一个参数是**插件 id**（`inlineKeyboard`），不是显示名。读取一个未声明的属性
  （在没声明它的组件上读 `root.pluginId`）会得到 `undefined`，于是所有字符串静默退回英文，
  journal 里一个错误都没有 —— 这个失败现象和「译文没加载」一模一样。

## 实际验证

不是「写完觉得应该能跑」，下面这些都在真实硬件上跑过（主机 + 带触摸屏的小米平板 5），并且
有单测或 IPC/诊断输出作证：

| 方面 | 怎么验的 |
|---|---|
| 纯逻辑（动作表、拖拽计划、修饰键状态机、候选切分、缩放算式、特殊键表） | `node --test tests/` —— **188 条断言** |
| addon 协议（状态推送、全量候选、按键/选词/提交） | 对活着的 fcitx5 双向跑通；journal 里每次状态变化一行 |
| 按键注入 | 两台设备上都真的打进过应用 |
| 键盘内候选 + 拼音串 | rime 万象实打，候选列表开/关/滚动 |
| 输入法切换（地球键、长按选择器） | 在平板上点过；空格键上的标识跟着每次点击变 |
| 停靠/浮动切换、位置拖动、缩画面板、透明度面板 | 平板上用过；几何以 IPC 返回值为准，不靠截图 |
| 表情 / 符号插入 | 硬件上点过；没有 addon 时回落到 `dms cl copy` |
| 翻译（zh_CN） | 运行时切换字符串并对着屏幕比对 |

这样查出来的回归，记录为源码里的提交，而不是这份 README 里的口头保证。

## AI 参与

这个插件是在**大量 AI 辅助下做出来的** —— 借助 Hermes Agent（一个 AI 编码代理）与作者结对
完成。设计决定由作者拍板，每次构建都在真实设备上测过，中间也否掉过不少弯路。

之所以写清楚，是因为这对评估代码的人很重要：

- **「实际验证」里每一条都真的执行过。** 测试跑过；addon 对着活着的 fcitx5 双向跑通过；
  键盘在两台机器上的真实应用里打出过字。这里没有一条建立在「代码看着对」上。
- **AI 写的代码和别的代码一样要过审。** 命名、重复、注释准确性和错误处理按本仓库自己的
  标准来；单测和真正的 QML 解析（`qmlformat`）是每次改动的门禁。
- **坦白的已知短板：** QML 表层（布局、手势手感和视觉对齐）是 AI 最不擅长的部分。这些
  地方都是对着真实触摸反复调出来的，`### IPC` 里那些诊断命令之所以存在，一部分原因就是
  这个调试回路。预期纯逻辑模块最靠谱，手势/动画这类打磨最「手工」。
- **没有一行 AI 生成的代码是没跑过就合进来的。** 如果你发现哪里和上面的表矛盾，那就是
  bug，请开 issue。


GPL-3.0-only。

## 打字是怎么走通的

每个按键事件都走同一条路径：

```
Key.qml (label/modifier state)  →  KeyboardCard.keyPressed  →  InlineKeyboardDaemon.handleKey
   ├─ stub / page   →  handled locally (toast / page switch)
   ├─ modifier key  →  cycleModifier() (0 / one-shot / locked)
   └─ anything else →  injectKey(code)
                          ↓  shape: [modifier presses] code:1 code:0 [modifier releases]
                       `ydotool key 42:1 30:1 30:0 42:0`     ← shift + a = "A"
```

`ydotoold` 是硬依赖：它的 socket（`$XDG_RUNTIME_DIR/.ydotool_socket`）不在时，注入直接返回，
设置页会显示一条带**启动**按钮的警告。`KeyboardCard` 从不直接和合成器打交道 —— 它只渲染
状态、上报按键。

Shift 被折进修饰键序列（而不是折进字符本身），这就是为什么 `Shift+A` 真的产出 `A`、
`Shift+1` 产出 `!` —— 这是键位表干的，不是我们。
