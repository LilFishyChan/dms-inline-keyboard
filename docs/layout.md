# 键盘布局与几何（对应当前实现）

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
unit   = (cardW - 2*pad - (15-1)*gap) / 15          // 一行 15 个单位
kbHeight = 2*pad + 0.78*keyH + gap
         + rows*keyH + (rows-1)*gap
         + 0.5*keyH                                  // 快捷条 0.78 / 把手 0.5 键高
keyH   = 反解上式（Math.max(28, …)）
```

- 默认名义尺寸 `kbWidth = 1050`、`kbHeight = 444`（`InlineKeyboardDaemon.qml` 的 `baseKbWidth/baseKbHeight`），乘以设置页的缩放（50–100%）。
- 键宽按单位算：`w*unit + (w-1)*gap` —— 这样底行只有 8 个键也能和上面 15 个键的行右边缘对齐。
- 不能用 `card.width / card.height` 反算：那是「窗口 ← 卡片 ← 窗口」的正反馈，浮动窗口一拖就自我收缩。

## 键位（`layouts/phone.js`）

`page1` 是主键区（数字行带 Fn 层 Esc/F1–F12，QWERTY 三行，底行 Ctrl/Win/Alt/空格/Fn/菜单/表情/第二页），
`page2` 是 F 区 + 导航 + 小键盘（15 列，中间留空列做分区）。
跨行键用 `rs: 2`（小键盘 `+` 和 Enter），`k: "spacer"` 只是占位、不按键面。

## 键位语义：现在 vs 计划

| 键 | 现在 | 计划 |
|---|---|---|
| `fn` / `page` | 改键盘自身状态（Fn 层、换页） | — |
| Shift / Caps Lock / Ctrl / Alt / Win | 三态切换（见下节），UI 立刻反映 | 注入时按状态决定修饰键是否按下 |
| 字符 / 空格 | **只是发 `keyPressed`，注入还没接** | `ydotool` 注入 keycode |
| 空格中间的输入法图标 | 显示 fcitx5 当前图标，点击仍是空格 | 有候选时点空格选第一个候选 |
| 撤销 / 重做 / 下个输入法 | 已经通过 `ydotool` / `fcitx5-remote` 真的执行 | — |

## 修饰键三态

状态：`0` 未激活 / `1` 激活（按下普通键即取消）/ `2` 锁定（只有再点本键才取消）。
`modifiers.js` 里是纯逻辑（有单测），daemon 持有状态、卡片按 `keyData` 查表。

| 状态 | 视觉（浅色主题实测） |
|---|---|
| 0 | 普通键 `surfaceContainer` #ffe1e8 / 修饰键 `surfaceContainerHighest` #ffd1dd |
| 1 | 底色不变，2px `primary` 描边 + `primary` 文字 |
| 2 | `primary` 实心 #af203e + `onPrimary` #ffefef |

> 两档强调靠「填充 / 描边 / 实心」的形状差异区分，不靠透明度：alpha 在浅色与深色主题下
> 混合结果不同，形状差异才稳。也不要拿 `Theme.primaryContainer` 做激活态——DMS 会给容器色
> 叠一层 elevation 淡化，浅色主题下它是 #ffd2d4，和键面 #ffd1dd 几乎同色，等于没有反馈。
> 动作磁贴的激活态表示的是「持久状态」，所以用实心 `primary`（和锁定同色）。

点一次（或按住）之后怎么走，由设置页的「修饰键切换方式」决定（`modifierMode`）：

| 模式 | 触摸 | 普通键按下时 |
|---|---|---|
| 按住才生效 `noLock` | 按下 → 1，松手 → 0；点一下不留状态 | — |
| 点击激活 `toggle` | 点一下 0 ⇄ 1 | 取消 |
| 单击锁定 `tapLock` | 点一下 0 ⇄ 2 | 锁定保留 |
| 单击切换、双击锁定 `doubleTapLock`（默认） | 点 → 1；同键 300ms 内再点 → 2；点 2 → 0 | 清 1，保留 2 |

即 `doubleTapLock` = 单击等价 `toggle`、双击等价 `tapLock`。

- Caps Lock 不受这个设置影响，永远是 0 ⇄ 2 的传统开关，普通键不清。
- 按下/松开事件只为 `noLock` 接线；其它模式走点击。
- 改切换方式时会把残留状态清空（`clearModifierStates`）。
- 自测：`setModifierMode tapLock`、`tapModifier ctrl`、`pressModifier shift` /
  `releaseModifier shift`、`pressDebugKey 30`（普通键 A）、`modifierStates`（看全部状态）。

## 按压反馈

`Ripple.qml` 是「按下驻留」型：`press(x, y)` 从触点扩散并在按住期间保持不透明，
`release()` 才淡出（180 ms）。MouseArea 必须三个都接：

```qml
onPressed: mouse => r.press(mouse.x, mouse.y)
onReleased: r.release()
onCanceled: r.release()   // 按住后拖出去也得收掉
```

## 三种界面状态

- `mode: "keys"` —— 键区
- `mode: "functions"` —— 动作磁贴网格；`editing` 时进入拖放排序（列表 ↔ 快捷栏 ↔ 右上角槽）
- `mode: "transparency"` —— 背景 / 按键两条透明度滑块；左上是确认，右上是取消（恢复进面板前的值）

## 透明度的归属

背景与按键透明度由插件自己存（`bgOpacity` / `keyOpacity`），叠加方式：面板底色乘 `bgOpacity`，
每个键/磁贴乘 `keyOpacity`；禁用态额外乘 0.5。**不跟随 DMS 主题的 alpha**。

## 编辑态：固定栏与列表的落点

进入编辑态后，顶部固定栏和下方的动作列表都显示**松手后的样子**，而不是当前状态。

| 拖到哪 | 拖动时看到 | 松手结果 |
|---|---|---|
| 两个固定栏动作之间 | 该动作占住这个位置，其它动作让位 | 插入到这个索引 |
| 固定栏最左 / 最右外侧 | 同上，索引 0 / 末尾 | 插到头 / 尾 |
| 固定栏已满 | 末尾那个变成列表**第一个**的幽灵块 | 末尾动作被挤回列表 |
| 右上角圆形槽 | 槽里显示拖来的图标 | 动作占槽，原槽动作回列表 |
| 拖回列表 | 列表在落点处裂开一个空位 | 从固定栏移除，回到列表 |

- 落点索引由 `Actions.quickBarInsertIndex(ghostX, count, slotW, slotGap)` 按跟手块
  中心算；最终数组由 `Actions.planQuickBarDrop` 生成——预览和真正落盘调的是同一个
  函数，所以看到的和得到的不可能不一致（两者都有单测）。
- 容量 `min(6, floor((midW + gap) / (slotW + gap)))`，随键盘宽度变；满了挤出的
  永远是**末尾**那一个，放进动作表最前面，因此列表里它出现在第一个。
- 幽灵块（固定栏里被插入的那项、列表里被挤出的那项）用 55% 不透明度 + 2px
  `primary` 描边；跟手块在固定栏上方**不淡化**——预览已经由幽灵块表达，两个都半透明
  就看不清拖的是什么了。
- 固定栏动作块是胶囊形，编辑态底色是 `surfaceContainerLow` 胶囊，`primary` 边框按
  内部动作范围画：没有动作就不画；有动作时从第一个动作左侧一个键间距到最后一个动作
  右侧一个键间距。
