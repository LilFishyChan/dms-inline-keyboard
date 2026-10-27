// 动作列表的纯逻辑：清洗、排序、可见性拆分。
// 不依赖 QML，可用 node --test 直接测试（见 tests/actions.test.js）。
//
// 数据结构：动作 = { id, label, icon, hidden?, builtin? }
//   hidden  —— 列表里不显示（固定栏/槽里已放的不受影响），内置动作只能隐藏不能删
//   builtin —— 来自默认动作表，设置页不允许删除
//   cmd     —— 自定义动作要执行的 shell 命令（内置动作没有，走插件内部逻辑）
//
// ⚠ 所有对外函数的第一步都要过 toArray()。QML 会把 .js 模块返回的数组、
// 以及 property var 里存的数组包成「类数组对象」，此时 Array.isArray() 是 false ——
// 直接判 Array.isArray 会让整个列表变成空（实测：拖一次动作进固定栏，列表就空了）。

/**
 * 转成真正的数组。Array.isArray 为真就原样返回，否则按 length 逐项搬运。
 * @param {*} value 任意值（可能是 QVariantList / QJSValue / 类数组）
 * @returns {Array} 真数组（引用可能不同，但元素是同一批对象）
 */
function toArray(value) {
    if (!value || typeof value === "string")
        return []
    if (Array.isArray(value))
        return value
    const out = []
    const n = value.length
    if (typeof n !== "number")
        return out
    for (let i = 0; i < n; i++)
        out.push(value[i])
    return out
}

/**
 * 清洗外部传入的动作列表：丢掉无效项、按 id 去重、补默认值。
 * @param {Array} raw 来自设置文件的原始数组（可能被污染）
 * @param {Array} fallback 全部无效时使用的默认动作
 * @returns {Array} 保证每项都有非空 id 的新数组
 */
function sanitizeActions(raw, fallback) {
    const source = toArray(raw)
    const fallbackList = toArray(fallback)
    if (source.length === 0)
        return fallbackList.slice()

    // 内置动作按 id 识别：老配置里没有 builtin 字段，靠默认动作表补上
    const builtinIds = {}
    for (let i = 0; i < fallbackList.length; i++) {
        if (fallbackList[i] && fallbackList[i].id)
            builtinIds[fallbackList[i].id] = true
    }

    const seen = {}
    const clean = []
    for (let i = 0; i < source.length; i++) {
        const action = source[i]
        if (!action || typeof action !== "object")
            continue
        const id = typeof action.id === "string" ? action.id.trim() : ""
        if (!id || seen[id])
            continue
        seen[id] = true
        clean.push({
            id: id,
            label: typeof action.label === "string" ? action.label : id,
            // 老配置里「悬浮」存的是字体图标名，迁移成插件自带的自绘 SVG
            icon: (id === "float" && (typeof action.icon !== "string"
                                      || action.icon === "" || action.icon === "dock"))
                  ? "icons/keyboard-float.svg"
                  : (typeof action.icon === "string" ? action.icon : ""),
            hidden: action.hidden === true,
            builtin: action.builtin === true || builtinIds[id] === true,
            cmd: typeof action.cmd === "string" ? action.cmd : ""
        })
    }
    return clean.length > 0 ? clean : fallbackList.slice()
}

/**
 * 在动作数组里把 fromId 移到 toId 的位置。
 * 用 id 而不是索引，避免 Repeater 重建后索引错位。
 * @returns {Array} 新数组；任一 id 不存在时返回原数组的副本
 */
function moveActionById(list, fromId, toId) {
    const copy = toArray(list).slice()
    if (fromId === toId)
        return copy
    let fromIndex = -1
    let toIndex = -1
    for (let i = 0; i < copy.length; i++) {
        if (copy[i] && copy[i].id === fromId) fromIndex = i
        if (copy[i] && copy[i].id === toId) toIndex = i
    }
    if (fromIndex < 0 || toIndex < 0)
        return copy
    const item = copy.splice(fromIndex, 1)[0]
    copy.splice(toIndex, 0, item)
    return copy
}

/**
 * 拆出「列表中可见的动作」——已经在固定槽或快捷栏里的不再重复显示。
 * @param {Array} all 完整动作数组（有序）
 * @param {string} slotActionId 右上角槽内的动作 id，空串表示槽为空
 * @param {Array} quickBarActions 快捷栏动作数组
 * @returns {Array} 可见动作，保持 all 的相对顺序
 */
function visibleActions(all, slotActionId, quickBarActions) {
    const source = toArray(all)
    if (source.length === 0)
        return []
    const hidden = {}
    if (slotActionId)
        hidden[slotActionId] = true
    const barItems = toArray(quickBarActions)
    for (let i = 0; i < barItems.length; i++) {
        const a = barItems[i]
        if (a && a.id) hidden[a.id] = true
    }
    // hidden 的动作不进列表；它若在固定栏/槽里仍然正常工作
    return source.filter(a => a && a.id && !hidden[a.id] && a.hidden !== true)
}

/**
 * 列表内部拖动的落点索引。
 * @param {number} ghostX 跟手块中心 x（列表内容坐标系）
 * @param {number} ghostY 跟手块中心 y（列表内容坐标系）
 * @param {number} contentWidth 列表可视宽度
 * @param {number} count 当前可见动作数量
 * @param {number} cellHeight 单格高度
 * @param {number} gap 格子间距
 * @param {number} columns 列数
 * @returns {number} 0..count-1 的落点索引
 */
function dropIndexAt(ghostX, ghostY, contentWidth, count, cellHeight, gap, columns) {
    if (count <= 0)
        return -1
    const cellWidth = (contentWidth - (columns - 1) * gap) / columns
    const col = Math.max(0, Math.min(columns - 1, Math.floor(ghostX / (cellWidth + gap))))
    const row = Math.max(0, Math.floor(ghostY / (cellHeight + gap)))
    const index = row * columns + col
    // 落在最后一项之后 → count（追加到末尾）。
    // 之前一律夹到 count-1，拖到末尾只能插到倒数第一个前面
    if (index >= count)
        return count
    const lastCol = (count - 1) % columns
    const lastRow = Math.floor((count - 1) / columns)
    if (row >= lastRow && col === lastCol) {
        const cellLeft = lastCol * (cellWidth + gap)
        if (ghostX > cellLeft + cellWidth / 2)
            return count
    }
    return index
}

/**
 * 把某个动作挪到数组末尾。
 * @returns {Array} 新数组；id 不存在或本来就在末尾时返回副本
 */
function moveActionToEndById(list, id) {
    const source = toArray(list).slice()
    let from = -1
    for (let i = 0; i < source.length; i++) {
        if (source[i] && source[i].id === id) {
            from = i
            break
        }
    }
    if (from < 0 || from === source.length - 1)
        return source
    const item = source.splice(from, 1)[0]
    source.push(item)
    return source
}

/**
 * 固定栏的插入位置：按跟手块中心 x 落在哪个间隙。
 * @param {number} ghostX 跟手块中心 x（固定栏本地坐标，相对 midX）
 * @param {number} count 固定栏现有动作数量
 * @param {number} slotW 单个动作块宽度
 * @param {number} slotGap 动作块之间的间距（两端也有）
 * @returns {number} 0..count 的插入位置
 */
function quickBarInsertIndex(ghostX, count, slotW, slotGap) {
    if (count <= 0)
        return 0
    let index = 0
    for (let i = 0; i < count; i++) {
        const center = (i + 1) * slotGap + i * slotW + slotW / 2
        if (ghostX < center)
            break
        index = i + 1
    }
    return Math.max(0, Math.min(count, index))
}

/**
 * 把动作落到固定栏时的最终结果。拖动预览和真正落盘共用这一份逻辑。
 *
 * 规则：插到 index；固定栏满了就把末尾那个挤出，放进动作表的最前面
 * （列表里它自然显示在第一个，因为它已经不在固定栏了）。
 *
 * @param {Object} opts
 * @param {Array} opts.bar 当前固定栏
 * @param {Array} opts.actionList 完整动作表（有序）
 * @param {Object} opts.action 被拖的动作
 * @param {number} opts.index 插入位置 0..bar.length
 * @param {number} opts.capacity 固定栏容量
 * @param {string} [opts.slotActionId] 右上角槽里的动作 id
 * @param {string} [opts.source] "" 列表 / "bar" 固定栏 / "slot" 槽
 * @param {number} [opts.sourceIndex] 源在固定栏里的索引（source === "bar" 时有效）
 * @returns {{bar: Array, actionList: Array, slotActionId: string, ejected: Object|null, insertedAt: number}}
 */
function planQuickBarDrop(opts) {
    const options = opts || {}
    const bar = toArray(options.bar).slice()
    const actionList = toArray(options.actionList).slice()
    const action = options.action
    const capacity = Math.max(1, Math.floor(options.capacity || 1))
    let slotActionId = options.slotActionId || ""
    const source = options.source || ""

    if (!action)
        return { bar: bar, actionList: actionList, slotActionId: slotActionId, ejected: null, insertedAt: -1 }

    let index = Number.isFinite(options.index) ? options.index : bar.length

    // 源就在固定栏里：先摘掉它自己，插入位置跟着前移
    if (source === "bar" && options.sourceIndex >= 0 && options.sourceIndex < bar.length) {
        bar.splice(options.sourceIndex, 1)
        if (index > options.sourceIndex)
            index -= 1
    }
    // 源在槽里：槽被清空
    if (source === "slot")
        slotActionId = ""

    // 防御：动作已经在这个固定栏里了（界面数据不同步时会这样），先摘掉再插，别插出重复项
    const existing = bar.findIndex(a => a && action.id && a.id === action.id)
    if (existing >= 0) {
        bar.splice(existing, 1)
        if (index > existing)
            index -= 1
    }

    index = Math.max(0, Math.min(bar.length, index))
    bar.splice(index, 0, action)

    // 满了：挤出末尾那一项（但不能把刚拖进来的自己挤掉，否则等于没插入）
    let ejected = null
    while (bar.length > capacity) {
        let outIndex = bar.length - 1
        if (bar[outIndex] === action && bar.length > 1)
            outIndex = bar.length - 2
        ejected = bar.splice(outIndex, 1)[0]
        const rest = actionList.filter(a => a && a.id !== ejected.id)
        rest.unshift(ejected)
        actionList.length = 0
        rest.forEach(a => actionList.push(a))
    }

    return {
        bar: bar,
        actionList: actionList,
        slotActionId: slotActionId,
        ejected: ejected,
        insertedAt: bar.indexOf(action)
    }
}

/**
 * 固定栏在拖动过程中应该渲染成什么样。
 * 优先级：落点预览(plan) > 松手后的冻结(frozen) > 拖走源动作后的真实数组 > 真实数组。
 *
 * 「拖走源动作」这条容易漏：从固定栏往外拖时落点不在固定栏（plan 为 null），
 * 若不把源动作从预览里摘掉，它会一直留在固定栏上，后面那些动作也不会补齐。
 *
 * @param {Object} opts
 * @param {Array} opts.bar 真实固定栏动作
 * @param {Object|null} opts.plan 落在固定栏内时的 planQuickBarDrop 结果
 * @param {Array|null} opts.frozen 松手后短暂冻结的数组
 * @param {boolean} [opts.dragActive] 是否正在拖动
 * @param {string} [opts.dragFrom] 拖动源 "bar" / "slot" / ""
 * @param {number} [opts.dragFromIndex] 源在固定栏里的索引
 * @returns {Array} 用于渲染的数组（真数组）
 */
function quickBarViewActions(opts) {
    const options = opts || {}
    if (options.plan)
        return toArray(options.plan.bar)
    if (options.frozen)
        return toArray(options.frozen)
    const bar = toArray(options.bar)
    const from = options.dragFromIndex
    if (options.dragActive && options.dragFrom === "bar"
            && typeof from === "number" && from >= 0 && from < bar.length) {
        const visible = []
        for (let i = 0; i < bar.length; i++) {
            if (i !== from)
                visible.push(bar[i])
        }
        return visible
    }
    return bar
}

/**
 * 内置动作表。daemon 和设置页共用这一份（label 是 i18n 源串）。
 * 返回新数组，调用方可以随便改。
 * @returns {Array} 带 builtin: true 的动作
 */
function defaultActions() {
    return markBuiltin([
        { id: "undo", label: "Undo", icon: "undo" },
        { id: "redo", label: "Redo", icon: "redo" },
        { id: "settings", label: "Settings", icon: "settings" },
        { id: "float", label: "Float", icon: "icons/keyboard-float.svg" },
        { id: "size", label: "Size", icon: "aspect_ratio" },
        { id: "opacity", label: "Opacity", icon: "opacity" },
        { id: "nextIm", label: "Next input method", icon: "language" },
        { id: "clipboard", label: "Clipboard", icon: "content_paste" },
        { id: "avoid", label: "Avoid windows", icon: "unfold_more" },
        { id: "mic", label: "Voice input", icon: "mic" }
    ])
}

/**
 * 给一批默认动作打上 builtin 标记（默认动作在设置页里只能隐藏、不能删除）。
 * @param {Array} list 默认动作
 * @returns {Array} 带 builtin: true 的副本
 */
function markBuiltin(list) {
    const source = toArray(list)
    const out = []
    for (let i = 0; i < source.length; i++) {
        const a = source[i]
        if (!a || !a.id)
            continue
        out.push({
            id: a.id,
            label: a.label || a.id,
            icon: a.icon || "",
            hidden: a.hidden === true,
            builtin: true
        })
    }
    return out
}

/**
 * 删除一个动作。内置动作不允许删除（返回原数组 + removed=false）。
 * @returns {{actions: Array, removed: boolean}}
 */
function removeAction(list, id) {
    const source = toArray(list)
    const out = []
    let removed = false
    for (let i = 0; i < source.length; i++) {
        const a = source[i]
        if (a && a.id === id) {
            if (a.builtin === true) {
                out.push(a)
                continue
            }
            removed = true
            continue
        }
        if (a)
            out.push(a)
    }
    return { actions: out, removed: removed }
}

/**
 * 改某个动作的字段（icon / label / hidden）。找不到就原样返回。
 * @returns {Array} 新数组
 */
function updateAction(list, id, patch) {
    const source = toArray(list)
    const out = []
    for (let i = 0; i < source.length; i++) {
        const a = source[i]
        if (!a || a.id !== id) {
            if (a)
                out.push(a)
            continue
        }
        const next = { id: a.id, label: a.label, icon: a.icon,
                       hidden: a.hidden === true, builtin: a.builtin === true,
                       cmd: typeof a.cmd === "string" ? a.cmd : "" }
        if (patch && typeof patch.label === "string")
            next.label = patch.label
        if (patch && typeof patch.icon === "string")
            next.icon = patch.icon
        if (patch && typeof patch.cmd === "string")
            next.cmd = patch.cmd
        if (patch && typeof patch.hidden === "boolean")
            next.hidden = patch.hidden
        out.push(next)
    }
    return out
}

/**
 * 追加自定义动作。id 用 "u<时间戳><序号>" 避免和内置 id 撞。
 * @returns {{actions: Array, action: Object}}
 */
function appendAction(list, action, seed) {
    const source = toArray(list).slice()
    const base = (action && action.id) || ("u" + (seed || Date.now()))
    let id = base
    let n = 2
    const taken = {}
    for (let i = 0; i < source.length; i++) {
        if (source[i] && source[i].id)
            taken[source[i].id] = true
    }
    while (taken[id])
        id = base + "_" + (n++)
    const created = {
        id: id,
        label: (action && action.label) || "(unnamed)",
        icon: (action && action.icon) || "label",
        cmd: (action && typeof action.cmd === "string") ? action.cmd : "",
        hidden: false,
        builtin: false
    }
    source.push(created)
    return { actions: source, action: created }
}

// node 测试用；QML 的 import "actions.js" 不读这里
if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        toArray, sanitizeActions, moveActionById, visibleActions, dropIndexAt,
        quickBarInsertIndex, planQuickBarDrop, quickBarViewActions, moveActionToEndById,
        defaultActions, markBuiltin, removeAction, updateAction, appendAction
    }
}
