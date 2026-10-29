.pragma library

// 特殊键的表现形式：图标 / 缩写 / 完整。
//
// 同一套键盘上 Backspace、Enter 这些键既有「一眼认形状」的需求（图标），
// 也有「一眼读名字」的需求（完整文字），还有人嫌完整文字太长挤。做成设置项，
// 三种形态由用户选。完整形态的超宽文字由 Key.qml 的
// Text.HorizontalFit 自动缩字号，不需要在这里算宽度。
//
// Win 键例外：它不代表某个固定动作（不同桌面环境下可能是 Mod / Super /
// Windows 键），所以它的表现单独由 winLook 决定，不受全局 style 影响。

// 每个特殊键的三种形态。
// icon 留空表示该键没有合适的图标，选「图标」时回落到简写。
// short 一律用文字，不用 ⌫ ↵ ⇧ 这类符号。
const SPECIAL_KEYS = {
    "Backspace": { icon: "backspace",          short: "Back",  full: "Backspace" },
    "Enter":     { icon: "keyboard_return",    short: "Enter", full: "Enter" },
    "Shift":     { icon: "shift",              short: "Shift", full: "Shift" },
    "Tab":       { icon: "keyboard_tab",       short: "Tab",   full: "Tab" },
    "Caps Lock": { icon: "keyboard_capslock",  short: "Caps",  full: "Caps Lock" },
    "Ctrl":      { icon: "",                   short: "Ctrl",  full: "Ctrl" },
    "Alt":       { icon: "",                   short: "Alt",   full: "Alt" },
    "Fn":        { icon: "",                   short: "Fn",    full: "Fn" },
    "Esc":       { icon: "",                   short: "Esc",   full: "Esc" },
    // 图标名必须是 Material Symbols 字体里真实存在的连字，
    // 写错不会报错、只是画不出字形 —— 键帽看起来是空的。
    // Del 不配图标（Material 里没有合适的删除键符号，垃圾桶语义也不对）：
    // icon 留空 → 「图标」形态下回落成 "Del" 文字，和 Ctrl / Alt / Esc 一样。
    // 原来写的 "backspace_outline" 字体里根本不存在（只有 backspace），所以是空键帽。
    "Del":       { icon: "",                   short: "Del",   full: "Del" },
    "Ins":       { icon: "",                   short: "Ins",   full: "Ins" },
    "Home":      { icon: "",                   short: "Home",  full: "Home" },
    "End":       { icon: "",                   short: "End",   full: "End" },
    "PgUp":      { icon: "",                   short: "PgUp",  full: "PgUp" },
    "PgDn":      { icon: "",                   short: "PgDn",  full: "PgDn" },
    "Print":     { icon: "",                   short: "PrtSc", full: "Print" },
    "NumLk":     { icon: "",                   short: "Num",   full: "NumLk" },
}

// Win 键的几种表现。默认 mod：它在这个键盘上实际发的是 Super_L，
// 叫 Win 只对 Windows 用户成立，叫 Mod 才是通用的。
const WIN_LOOKS = {
    "mod":    { icon: "",                     text: "Mod" },
    "super":  { icon: "",                     text: "Super" },
    "system": { icon: "keyboard_command_key", text: "" },
    // 自定义：图标名由设置项 winKeyCustomIcon 提供
    "custom": { icon: "",                     text: "" },
}

// 这种 label 是不是「特殊键」（决定要不要套用设置里的形态）
function isSpecialKey(label) {
    if (!label)
        return false
    return label === "Win" || Object.prototype.hasOwnProperty.call(SPECIAL_KEYS, label)
}

// 算出这个键该画图标还是文字。
// 返回 { icon, text }：icon 非空就画图标，否则画 text。
function resolve(label, style, winLook, winCustomIcon) {
    if (!isSpecialKey(label))
        return { icon: "", text: label || "" }

    if (label === "Win") {
        const w = WIN_LOOKS[winLook] || WIN_LOOKS["mod"]
        if (winLook === "custom") {
            // 没填图标就退回 Mod 文字，别留个空键帽
            const custom = typeof winCustomIcon === "string" ? winCustomIcon.trim() : ""
            return custom
                ? { icon: custom, text: "" }
                : { icon: "", text: WIN_LOOKS["mod"].text }
        }
        return { icon: w.icon, text: w.text }
    }

    const entry = SPECIAL_KEYS[label]
    // 选「图标」但这键没有图标 → 回落到缩写，不要留个空键帽
    if (style === "icon")
        return entry.icon
            ? { icon: entry.icon, text: "" }
            : { icon: "", text: entry.short }
    if (style === "short")
        return { icon: "", text: entry.short }
    return { icon: "", text: entry.full }
}

// 设置项可选值（设置页和校验共用，避免两处各写一份字符串）
const STYLES = ["icon", "short", "full"]
const WIN_LOOK_KEYS = ["mod", "super", "system", "custom"]

function normalizeStyle(style) {
    return STYLES.indexOf(style) >= 0 ? style : "full"
}

function normalizeWinLook(look) {
    // "windows" 已移除，老配置迁移到 system（同一个 ⌘ 图标）
    if (look === "windows")
        return "system"
    return WIN_LOOK_KEYS.indexOf(look) >= 0 ? look : "mod"
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        SPECIAL_KEYS: SPECIAL_KEYS,
        WIN_LOOKS: WIN_LOOKS,
        STYLES: STYLES,
        WIN_LOOK_KEYS: WIN_LOOK_KEYS,
        isSpecialKey: isSpecialKey,
        resolve: resolve,
        normalizeStyle: normalizeStyle,
        normalizeWinLook: normalizeWinLook
    }
}
