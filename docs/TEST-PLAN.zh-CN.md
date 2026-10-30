# Inline Keyboard 功能与测试清单

**简体中文** · [English](TEST-PLAN.md)

自动测试只能守住纯逻辑：画出来的东西、手势、和真实合成器的交互都得人来过一遍。
这份清单把全部功能按线拆开，标出哪部分由 `node --test` 负责、哪部分必须手工验。

```bash
node --test tests/          # 243 条，纯逻辑层
```

---

## 一、自动化覆盖（不用手测）

| 文件 | 用例 | 守住什么 |
|---|---:|---|
| `tests/actions.test.js` | 80 | 动作表清洗与合并、拖放排序与落点换算、固定栏容量与挤出、可见性过滤 |
| `tests/data.test.js` | 53 | addon JSON 解析与降级、输入法行构造与地球键循环、候选切分、Esc↔\` 对调 |
| `tests/modifiers.test.js` | 40 | 修饰键四档状态机、Caps、Fn / page、组合键按下序列 |
| `tests/resize.test.js` | 23 | 拖拽调尺寸、上下限、对称与等比、持久化值归一 |
| `tests/special-keys.test.js` | 14 | 特殊键的文字 / 缩写 / 图标三种形态 |
| `tests/keyroute.test.js` | 13 | 按键交给 fcitx5 还是 ydotool |
| `tests/candidates.test.js` | 10 | 候选分行与宽度分配（不截断、贴右边） |
| `tests/emoji.test.js` | 5 | 表情分组完整性、上屏协议（不含换行） |
| `tests/layout.test.js` | 5 | 布局结构、换页键目标、键位不重叠 |

只改下列文件时，跑一遍单测即可：

- `actions.js`、`data.js`、`keyroute.js`、`candidates.js`、`modifiers.js`
- `layouts/phone.js`、`layouts/emoji.js`、`layouts/resize.js`、`layouts/special-keys.js`

改 QML 组件、窗口、手势、设置页 → 必须走后面的手工清单。

### 半自动：分 8 块的验收脚本

`scripts/acceptance.py` 按功能域切成 8 块，**可以只跑受影响的那一块**：

```bash
python3 scripts/acceptance.py               # 全量（约 1.5 分钟）
python3 scripts/acceptance.py keys          # 只跑键位（约 50 秒）
python3 scripts/acceptance.py keys drag     # 跑两块
python3 scripts/acceptance.py --list        # 列出块和子块数
```

| 块 | 覆盖 | 什么时候单跑 |
|---|---|---|
| `keys` | page1 50 键 / page2 41 键全量遍历、Fn 层、Shift 层、页面键四档、修饰键、干跑 | 改键位数据、`keyroute.js`、`modifiers.js`、页面键 |
| `cand` | 候选注入、顶栏/列表切分、展开收起、侧键、地球键循环 | 改 `CandidateBar` / `CandidatePanel` / `candidates.js` / fcitx 桥 |
| `pages` | 表情页进/出、符号段、分类 chip | 改 `EmojiPanel` / `EmojiCategoryBar` / `layouts/emoji.js` |
| `act` | 右上角槽、导航、磁贴、透明度面板、最小化、关→开 | 改 `QuickBar` / `ActionList` / 动作表 |
| `geo` | 尺寸、透明度、浮动位置（设 → 读回 → 还原） | 改 `resize.js` / 几何相关 |
| `drag` | 点击、长按 800ms、拖到卡片外、固定栏拖动 | 改 `DragInitiator` / `DragGhost` / 落点判据 |
| `settings` | 临时改设置（escSwap / dockFillWidth / specialKeyStyle / slotActionId / bgOpacity）→ 生效 → 还原 | 改设置项逻辑 |
| `env` | 设置落盘 → 重启 → 读回、重启后 journal 冒烟 | 改设置读写、`plugin.json`、包体结构 |

三条约定：

- **每块自己收尾**（还原设置 / 清候选 / 回第一页），所以任意组合、任意顺序都不会互相污染
- **真正的按键点击前必过守卫**：回读 `now=on` 确认干跑开着 → 点一个普通键 → 点一个可重复键并停 0.9 秒看记录仍只有 2 条 → addon 日志计数不动 → 键盘仍打开。任一不过就中止，一个键都不再点。这挡的是「连发点击吃掉 release → 可重复键长按重复失控 → 把输入法刷崩」
- 断言的是**状态**不是画面，所以清单里属于「视觉 / 手感」的条目仍要人过

### 模拟使用流程：点击 / 长按 / 拖动

这三类操作都是**在插件内部注入**的 —— 调的是用户操作本来就会触发的那几个函数，
不经过系统输入、不移动鼠标、不依赖屏幕坐标：

所有点击都走同一个入口 `debugTap <目标> <参数1> <参数2>`，内部按目标分发：

| 目标 | 参数 | 点的是 |
|---|---|---|
| `key` | 标签, 按住毫秒 | 按键自己的 `pressAt → releaseAt → clickAt`（长按重复、修饰键都会真实触发） |
| `expand` | — | 候选栏右侧展开按钮 |
| `side` | `up` / `down` / `backspace` / `enter` | 候选列表右侧按钮 |
| `bottom` | `close` / `lang` | 底部关闭键 / 地球键 |
| `nav` | — | 顶部导航键（keys ↔ functions） |
| `action` | 动作 id | 功能列表磁贴 |
| `bar` | 动作 id | 固定栏动作 |
| `slot` | — | 右上角动作槽（浮动开关） |
| `emojiCat` | 分组 id | 表情分类条 chip |

拖动另有两个入口：`debugDrag <index> <x> <y>` + `debugDrop`（固定栏用 `debugDragFromBar`），
走卡片真实的 `endDrag()` 落盘路径。

```bash
dms ipc call inlineKeyboard debugTap key layers 40      # 点页面键
dms ipc call inlineKeyboard debugTap key Ctrl 800       # 按住 Ctrl 800ms
dms ipc call inlineKeyboard debugTap expand "" 0        # 展开候选列表
dms ipc call inlineKeyboard debugTap side enter "" 0    # 候选列表的确认键
dms ipc call inlineKeyboard debugDrag 0 99999 99999     # 拖到卡片外（无效落点）
dms ipc call inlineKeyboard debugDrop
```

`key` 的标签取布局里的原文（`Enter` / `F1` / `A` / `↑` / `layers`，字母是大写）；
不用参数的目标传空字符串；坐标用大正数表示「卡片外」——负数会被 `dms ipc` 当成 flag。

### 干跑模式：只验证会发什么，不往系统输入

`debugSetDryRun true` 之后，按键不再真的注入 —— 只把「本来会发什么」记下来：

```bash
dms ipc call inlineKeyboard debugSetDryRun true
dms ipc call inlineKeyboard debugTap key Enter 40
dms ipc call inlineKeyboard debugInjected
#   INJECTED[1]:Enter/key/ydotool/28/m0
dms ipc call inlineKeyboard debugSetDryRun false
```

记录格式是 `标签/键类型/选路/键码/m修饰位`。`acceptance.py` 用它验证回车、退格、数字、
字母各自走哪条路，并用 addon 日志条数前后对比证明**一条都没真发出去**。
注意 bool 参数要传 `true` / `false`，传 `on` 会解析失败。

### 几何与透明度：读 / 写

```bash
dms ipc call inlineKeyboard debugGeometry
#   GEO:x=538 y=42 w=840 h=443 bg=73 key=100 float=0 dockFill=0 saved=840x457 screen=1920x1080 pos=-

dms ipc call inlineKeyboard debugSetSize 900 400       # → SIZE:900x400（夹进上下限后落盘）
dms ipc call inlineKeyboard debugSetOpacity 88 92      # → OPACITY:88/92（bg / key，0–100）
dms ipc call inlineKeyboard debugSetPosition 200 300   # 只在浮动模式可用 → POS:200,300
```

- `w/h` 是卡片**实际**尺寸，`saved` 是**落盘**的名义尺寸（两者差一个顶部留白，实测 14px）
- `pos` 只在浮动模式有值，停靠时是 `-`
- 三个写入走的都是界面操作同一条落盘路径，重启后保持
- 验收脚本里每次写入都「设 → 读回 → 还原」，不会把鱼鱼的设置改掉

### 为什么 QML 没有自动化

`qs.Common` / `qs.DCommon.Widgets` 编译在 `/usr/bin/dms` 的 qrc 里，独立进程加载不到；
本机 `qmltestrunner` 也跑不起来（读入测试文件后静默退出）。所以 QML 里的判据要么抽成
纯函数（`keyroute.js` / `candidates.js` 就是这么来的），要么只能手工验。

---

## 二、手工验收清单

规则：动到哪条线就过哪条线；发版前全过一遍。

### A. 窗口与形态

- [ ] `dms ipc call inlineKeyboard toggle` 能开能关，状态栏图标同步
- [ ] 停靠模式贴在屏幕下沿，别的窗口被顶上去、不被键盘盖住
- [ ] 停靠模式左右拖动底部把手：键盘跟手，松手停住
- [ ] 切浮动：能拖到任意位置（含状态栏上方），重开位置还在
- [ ] 最小化：只剩圆按钮；点一下恢复，形态和收起前一致
- [ ] 关闭再打开：page / mode / 尺寸 / 位置恢复上次状态
- [ ] 键盘窗口不吃焦点：注入的键落在应用上，不落到键盘自己
- [ ] 语音模式（装了 fcitx5-vinput）：语音行出现，识别文字进预编辑，再点麦克风结束

### B. 打字与按键

- [ ] 拼音输入：预编辑正常显示，空格上屏候选
- [ ] socket 断开 / 未装 addon 时仍能打字（回落 ydotool）
- [ ] 数字键（主键区和小键盘）打出来是数字，不会被 rime 当候选序号
- [ ] 符号键在中文模式下变全角 / 中文标点
- [ ] Shift：点一下一次性（打完一个字母自动松开）；双击锁定
- [ ] Caps Lock：锁定大小写，再点解除
- [ ] Fn 层：1–0 变 F1–F10，`-` `=` 变 F11 / F12
- [ ] 设置里开 `escSwap` 后左上角变 Esc，Fn 层仍能打出 \` 和 ~
- [ ] 长按退格连续删；长按字符键连续输入
- [ ] 第二页：方向键 / Home / End / PgUp / PgDn / Del / Ins 都生效
- [ ] 回车：**没有预编辑**时正常换行 / 提交（走真键）
- [ ] 回车：**有预编辑**时上屏当前候选
- [ ] 退格：无预编辑时删应用里的字；有预编辑时删拼音串
- [ ] 组合键 Ctrl+C / Ctrl+V / Alt+Tab 一次生效
- [ ] 地球键：单击循环输入法，长按出选择器
- [ ] 页面键：点一下进第二页、再点回第一页；`modifierMode` 四档行为都符合预期

### C. 候选

- [ ] 顶部候选条按宽度裁切，装不下的不显示；首项最长占 2/3
- [ ] 长词显示完整，不被压窄成省略号
- [ ] 点展开按钮进候选列表页，返回键退回键盘
- [ ] 列表页：词按行排列，分隔线在间距正中、行末不画
- [ ] 列表右侧四个按钮：上翻 / 下翻 / 退格 / 回车
- [ ] 点候选上屏，用的是原始下标（不是显示序号）
- [ ] 预编辑消失后列表页自动收起
- [ ] 无候选时显示「加载中 / 无候选」

### D. 表情与符号

- [ ] 表情键进表情页，左上角 X 回键盘
- [ ] 分类条切换分组，当前分组高亮
- [ ] 表情段 / 符号段切换
- [ ] 点表情上屏（addon 可用时直接提交，否则走剪贴板）
- [ ] 表情页退格键删字

### E. 动作系统

- [ ] 固定栏动作点击生效（关闭 / 浮动 / 避让 / 最小化 / 透明度 / 尺寸 / 剪贴板 / 撤销 / 重做 / 下一个输入法 / 设置 / 麦克风）
- [ ] 动作状态着色正确：浮动着色、避让在浮动时禁用
- [ ] 功能列表点动作生效
- [ ] 编辑态：列表内拖动排序，松手顺序落盘
- [ ] 固定栏内拖动排序，挤出的动作回到动作表
- [ ] 从固定栏 / 列表拖到右上角槽：两者交换，原槽动作回到腾出的格子
- [ ] 拖到键盘外松手：顺序不变，幽灵块回原位
- [ ] 设置页新增 / 修改 / 删除自定义动作，键盘上立刻可见

### F. 面板与设置

- [ ] 透明度面板：滑杆实时预览、取消还原、确认落盘
- [ ] 调整大小：四个把手各自生效；停靠拖左右时两边同时收放；浮动只动被拖的边
- [ ] 调整大小：四角等比；上下限生效；重置回名义尺寸；铺满切换
- [ ] 设置页各项改完立刻生效（不用重开键盘）
- [ ] `modifierMode` 四档：按住生效 / 点一下激活 / 点一下锁定 / 双击锁定
- [ ] `specialKeyStyle` / `winKeyStyle` / 自定义图标 立刻换样式

### G. 诊断

- [ ] `dms ipc call inlineKeyboard diag` 字段齐全（socket / im / cand / preedit / ydotoold / mods）
- [ ] 调试模式（设置页 → Debugging）打开时 `debug*` 可用；关掉一律返回 `dev mode off`
- [ ] `journalctl --user -u dms` 里没有本插件的 `ERROR qml` / `TypeError` / `Binding loop`

---

## 三、回归重点

这三处历史上都出过**静默失效**（不报错、只是不工作），改动相邻代码时优先过：

1. **按键路由**（`keyroute.js` + `KeyRouter.qml`）→ B 段的回车、退格、数字、组合键
2. **候选宽度**（`candidates.js` + `CandidatePanel.qml`）→ C 段的长词、右边界
3. **拖放落点**（`actions.js` + `QuickBar.qml` / `ActionList.qml`）→ E 段的排序与槽交换

## 四、验证记录

按版本往下记，每次发版补一行。

- **0.1.5** — 回车 / 退格 / F1 / 方向键改走真键（addon 日志 `key sent` 零增长）；候选行改「分配余量」（`fits=ok`，长词不截断）；页面键接入修饰键状态机；候选面板换 `DListView`；固定栏幽灵块 `targetX` 绑定循环消除
