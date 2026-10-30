.pragma library

// 特殊键三种形态：图标 / 缩写 / 完整。超宽文字由 Key.qml 自动缩字号。
// icon 留空表示没有合适图标（选图标时回落简写）；图标名必须是 Material 里真实存在的连字

// 每个特殊键的三种形态。
// icon 留空表示该键没有合适的图标，选「图标」时回落到简写。
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
