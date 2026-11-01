// 按键该交给输入法还是由合成器直接发：纯逻辑，node --test 可测。
// 判据只有一条 —— 这个键会不会产生文本。

var ROUTE = { fcitx: "fcitx", ydotool: "ydotool" }

var PRINTABLE = /^[\x20-\x7E]$/
var DIGIT = /^[0-9]$/

// 会产生文本、且输入法参与才有意义的键
function producesText(sym, kind, state) {
    // 有预编辑时空格交给输入法上屏；没有时输入法只会把它吞掉
    // （socket 注入的键转发不回焦点应用），必须发真键
    if (sym === "space")
        return !!state.preedit
    // 有预编辑时的 Backspace / Enter 要交给输入法删字、上屏
    if (state.preedit && (sym === "Backspace" || sym === "Enter"))
        return true
    if (!PRINTABLE.test(sym) || DIGIT.test(sym))
        return false
    // 小键盘符号是硬件键语义，过输入法会被转成中文标点
    return !(kind === "key")
}

function decideRoute(sym, kind, state) {
    const s = state || {}
    if (!sym || s.available === false)
        return ROUTE.ydotool
    // 纯键盘布局 / 英文模式 / 组合键：输入法帮不上忙，交给合成器
    if (s.imKeyboard || s.isAsciiMode || s.combo)
        return ROUTE.ydotool
    return producesText(sym, kind, s) ? ROUTE.fcitx : ROUTE.ydotool
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        ROUTE: ROUTE,
        producesText: producesText,
        decideRoute: decideRoute
    }
}
