// 修饰键纯逻辑：键码 → 名字、按下/松开/点按后的状态、普通键后的复位。node --test 可测。
// 状态 0 未激活 / 1 软激活（普通键取消）/ 2 锁定（只有再点本键才取消）

var MODES = {
    noLock: "noLock",
    toggle: "toggle",
    tapLock: "tapLock",
    doubleTapLock: "doubleTapLock"
}

var DEFAULT_MODE = MODES.doubleTapLock
var DEFAULT_DOUBLE_TAP_MS = 300

var MODIFIER_BY_KEYCODE = {
    58: "caps",
    29: "ctrl",
    56: "alt",
    125: "super"
}

var KEYCODE_BY_MODIFIER = {
    caps: 58,
    ctrl: 29,
    alt: 56,
    super: 125
}

/**
 * 从键位数据推出它是哪个修饰键，不是修饰键返回空串。
 * @param {Object} keyData layouts/phone.js 里的键定义
 * @returns {string} "shift" | "caps" | "ctrl" | "alt" | "super" | ""
 */
function modifierNameFor(keyData) {
    if (!keyData)
        return ""
    if (keyData.k === "shift")
        return "shift"
    // Fn 和 shift/ctrl/alt 走同一套状态机（0 关 / 1 一次性 / 2 锁定）
    if (keyData.k === "fn")
        return "fn"
    // 第二页开关走状态机：0 = 第一页 / >0 = 第二页。
    // 表情页那种也是 k === "page"，但它是普通跳转，不是「切到第二页」
    if (keyData.k === "page")
        return (keyData.to === "page1" || keyData.to === "page2") ? "page" : ""
    if (keyData.k !== "key")
        return ""
    return MODIFIER_BY_KEYCODE[keyData.c] || ""
}

/**
 * modifierNameFor 的逆运算：名字 → 键位数据（给调试 IPC 用）。
 * @param {string} name "shift" | "caps" | "ctrl" | "alt" | "super"
 * @returns {Object|null} 键位数据，未知名字返回 null
 */
function keyDataFor(name) {
    if (name === "shift")
        return { k: "shift" }
    if (name === "page")
        return { k: "page" }
    if (KEYCODE_BY_MODIFIER[name] !== undefined)
        return { k: "key", c: KEYCODE_BY_MODIFIER[name] }
    return null
}

/**
 * 点一下（按下并松开）之后的状态。
 * @param {Object} opts
 * @param {string} opts.name 修饰键名
 * @param {number} opts.current 当前状态 0/1/2
 * @param {string} [opts.mode] 切换方式，默认 doubleTapLock
 * @param {boolean} [opts.isSameKey] 上一次点的是不是同一个修饰键
 * @param {number} [opts.sinceLastTapMs] 距上一次点击的毫秒数
 * @param {number} [opts.doubleTapMs] 双击间隔，默认 300
 * @returns {number} 新状态
 */
function nextModifierState(opts) {
    const options = opts || {}
    const name = options.name || ""
    const current = options.current === 1 || options.current === 2 ? options.current : 0
    const mode = MODES[options.mode] ? options.mode : DEFAULT_MODE

    // caps lock 永远是传统开关
    if (name === "caps")
        return current === 2 ? 0 : 2

    // Fn 是「切层」不是「按住生效」，noLock 对它没意义 → 退化成传统开关
    // page 同理：切页只有「停在哪一页」有意义，按住切页等于锁定
    if ((name === "fn" || name === "page") && mode === MODES.noLock)
        return current === 2 ? 0 : 2

    if (mode === MODES.noLock)
        return current          // 激活靠按下/松开，点一下不改变状态

    if (mode === MODES.toggle)
        return current === 0 ? 1 : 0

    if (mode === MODES.tapLock)
        return current === 2 ? 0 : 2

    // doubleTapLock：单击 = toggle，双击 = 锁定
    const doubleTapMs = options.doubleTapMs > 0 ? options.doubleTapMs : DEFAULT_DOUBLE_TAP_MS
    if (current === 2)
        return 0
    if (current === 1) {
        const quick = options.isSameKey === true && options.sinceLastTapMs >= 0
                      && options.sinceLastTapMs < doubleTapMs
        return quick ? 2 : 0   // 间隔内再点 = 锁定；超时再点 = 取消
    }
    return 1
}

/**
 * 按下修饰键时的状态（只有 noLock 会变）。
 * @param {string} mode 切换方式
 * @param {number} current 当前状态
 * @param {string} [name] 修饰键名；page 不走「按住生效」
 * @returns {number} 新状态
 */
function pressModifierState(mode, current, name) {
    // page 键按住不切页：切页靠点击锁定，按住切页没有可用的手感
    if (name === "page")
        return current
    if (mode === MODES.noLock)
        return 1
    return current
}

/**
 * 松开修饰键时的状态（只有 noLock 会回落）。
 * @param {string} mode 切换方式
 * @param {number} current 当前状态
 * @param {string} [name] 修饰键名；page 不参与回落
 * @returns {number} 新状态
 */
function releaseModifierState(mode, current, name) {
    if (name === "page")
        return current
    if (mode === MODES.noLock)
        return 0
    return current
}

/**
 * 普通键按下之后：状态 1（软激活）清零，状态 2（锁定）与 caps lock 保留。
 * toggle 的激活态就是状态 1，所以这里不用按模式分支。
 * @param {Object} states { shift: 0, caps: 0, ... }
 * @returns {Object} 新对象（不改入参）
 */
// 修饰键的 Linux 输入键码
var MODIFIER_KEYCODES = {
    ctrl: 29,
    alt: 56,
    shift: 42,
    super: 125
}

/**
 * 把当前修饰键状态翻译成「按下 / 松开」序列。
 * 顺序固定（ctrl → alt → shift → super），松开时反序，避免组合键冲突。
 * @param {Object} states {shift, ctrl, alt, super, ...} 值 > 0 视为按下
 * @returns {{down: string[], up: string[]}} 形如 ["29:1"] / ["29:0"]
 */
function modifierSequence(states) {
    const source = states || {}
    const order = ["ctrl", "alt", "shift", "super"]
    const down = []
    const up = []
    for (let i = 0; i < order.length; i++) {
        const name = order[i]
        if ((source[name] || 0) > 0) {
            const code = MODIFIER_KEYCODES[name]
            down.push(code + ":1")
            up.unshift(code + ":0")
        }
    }
    return { down: down, up: up }
}

function clearTransient(states) {
    const source = states || {}
    const out = {}
    for (const name in source) {
        const state = source[name]
        out[name] = (name !== "caps" && state === 1) ? 0 : state
    }
    return out
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        MODES: MODES,
        DEFAULT_MODE: DEFAULT_MODE,
        DEFAULT_DOUBLE_TAP_MS: DEFAULT_DOUBLE_TAP_MS,
        modifierNameFor: modifierNameFor,
        keyDataFor: keyDataFor,
        nextModifierState: nextModifierState,
        pressModifierState: pressModifierState,
        releaseModifierState: releaseModifierState,
        clearTransient: clearTransient,
        MODIFIER_KEYCODES: MODIFIER_KEYCODES,
        modifierSequence: modifierSequence
    }
}
