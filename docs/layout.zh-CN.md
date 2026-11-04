# 键盘布局与几何（对应当前实现）

**简体中文** · [English](layout.md)

> 早期 v0.2 的原型规格（常驻数字行 + 数字页/符号页 + 三档键高）没有进入实现，
> 那份稿子已废弃。下面描述的是代码里实际跑的东西。

## 分区（自上而下）

1. **快捷栏**（`QuickBar.qml`）—— 左端导航/确认圆钮、中间快捷动作槽、右端圆形动作槽
2. **候选 / 快捷条**（`CandidateBar.qml`）—— `showCandBar` 打开时才占高度；候选数据仍是 demo
3. **主区**（三选一，高度恒定）—— 键区 / 功能动作列表 / 透明度面板
4. **把手条**（`BottomBar.qml`）—— 左端收起、中间拖动把手（仅浮动）、右端输入法切换

主区高度 = 5 行键高 + 4 个间距，功能页是「4 行滚动 + 1 行编辑按钮」，所以切页时卡片不会变高。

## 尺寸推导

全部集中在 `KeyboardMetrics.qml`（停靠 / 浮动两个窗口共用，别在窗口里另写一份）：

```text
cardW  = min(kbWidth, screenW - 24)
unit   = (cardW - 2*pad - (rowUnits-1)*gap) / rowUnits   // rowUnits 由布局决定：15 / 16
kbHeight = 2*pad + 0.78*keyH + gap
         + rows*keyH + (rows-1)*gap
         + 0.75*keyH                                 // 快捷条 0.78 / 把手 0.75 键高
keyH   = 反解上式（Math.max(28, …)）
```

- 名义尺寸按布局取（`InlineKeyboardDaemon.qml` 的 `baseKbWidth/baseKbHeight`）：
  `phone` = 1050×444（15 单位 × 5 行），`kb75` = 1120×510（16 单位 × 6 行）。
  这两个值是**反解出来的**：让两套布局在名义尺寸下的键宽高几乎相同
  （unit 63.4 vs 63.3，keyH 60.0 vs 60.0），换布局不会突然变出一堆小按键。
- 切换布局时 `applyLayoutSize()` 会按当前键宽高反解、再按新行列数算回去，
  用户自己拖过的尺寸也能保住；两者对不上才落盘。
- 键宽按单位算：`w*unit + (w-1)*gap` —— 这样底行只有 8 个键也能和上面 15 个键的行右边缘对齐。
- 不能用 `card.width / card.height` 反算：那是「窗口 ← 卡片 ← 窗口」的正反馈，浮动窗口一拖就自我收缩。

## 键位（`layouts/phone.js` / `layouts/kb75.js`）

两套布局，设置页「外观 → 键盘布局」切换，默认 `phone`：

| id | 行宽 | 行数 | 页 | 说明 |
|---|---|---|---|---|
| `phone` | 15 单位 | 5 | page1 / page2 | 紧凑：数字行带 Fn 层，F 区与导航在 page2 |
| `kb75` | 16 单位 | 6 | page1 | 75% 配列：F 区、导航列、方向键常驻，单页 |

`phone.js` 的 `page1` 是主键区（数字行带 Fn 层 Esc/F1–F12，QWERTY 三行，底行
Ctrl/Win/Alt/空格/Fn/菜单/表情/第二页），`page2` 是 F 区 + 导航 + 小键盘
（15 列，中间留空列做分区）。跨行键用 `rs: 2`（小键盘 `+` 和 Enter），`k: "spacer"`
只是占位、不按键面。

`kb75.js` 对应 QMK 的 `LAYOUT_75_ansi` 键序：F 区 16 键满行（Esc + F1–F12 + PrtSc/Pause/Del）、
右侧一列 Home/PgUp/PgDn/End、底行右端 ↑↓←→。**没有 page2、没有表情键、没有换页键**，
底行 16 单位正好被 `Ctrl Win Alt 空格(6.75) Alt Ctrl ←↓→` 排满；表情从内置动作进
（`actions.js` 的 `emoji`）。Fn 键先在 kb75 里留空位：把空格缩到 6.25、在 Alt 与 Ctrl 之间
插一个 1 单位的 `{k: "fn", l: "Fn", w: 1}` 就填满了。

两个模块的接口一致（`rowUnits` / `pageRows()` / `layoutFlat()`），QML 侧 import 两个别名、
按 `layoutId` 取用（`layoutModule`）——QML 的 import 是静态的，选不了模块。

## 按压反馈

按压反馈用 DMS 自带的 `DRipple`（`qs.DCommon.Widgets`），不再自带实现。
按下/松开的具体契约看组件本身，这里不重复描述，避免文档跟着组件漂移：

```qml
onPressed: mouse => r.press(mouse.x, mouse.y)
onReleased: r.release()
onCanceled: r.release()   // 按住后拖出去也得收掉
```

## 三种界面状态

- `mode: "keys"` —— 键区
- `mode: "functions"` —— 动作磁贴网格；`editing` 时进入拖放排序（列表 ↔ 快捷栏 ↔ 右上角槽）
- `mode: "transparency"` —— 背景 / 按键两条透明度滑块；左上是确认，右上是取消（恢复进面板前的值）

`mode` 管的是「主区显示哪块面板」；键位页是另一个维度（`page: page1 / page2 / emoji`）。
表情页占 `page: "emoji"`，主区换成 `EmojiPanel`：顶部那行（`quickH`）从快捷栏换成
`EmojiCategoryBar` 的分类条，中间是滚动网格，最后一行是「返回 / 表情·符号 / 退格」。
卡片高度仍然按主键区 5 行算，所以切到表情页键盘不会变高变矮。

## 透明度的归属

背景与按键透明度由插件自己存（`bgOpacity` / `keyOpacity`），叠加方式：面板底色乘 `bgOpacity`，
每个键/磁贴乘 `keyOpacity`；禁用态额外乘 0.5。**不跟随 DMS 主题的 alpha**。
