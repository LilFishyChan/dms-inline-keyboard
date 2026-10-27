.pragma library

// Inline Keyboard 布局数据。与 prototype/layout.js 同构（HTML 原型验证过的定稿）。
// 行宽统一 15 单位（真键盘主键区宽度）。
//
// 键字段：
//   k   kind：char 字符键 / key 键码键 / shift / space / page / spacer / fn / stub
//   l   下档字符（或功能键名）        s  上档符号（双行键面的上面那行）
//   c   Linux input-event keycode     w  宽度（单位，默认 1）
//   to  page 键的目标页               fn {l, c}  Fn 层激活时的替代标签与键码
//
// 页面：page1 主键区 / page2 F 区 + 导航 + 小键盘

var rowUnits = 15

var rows = {
    page1: [
        // 数字行（Fn 层：Esc / F1–F12）
        [
            {k: "char", l: "`", s: "~", c: 41, fn: {l: "Esc", c: 1}},
            {k: "char", l: "1", s: "!", c: 2, fn: {l: "F1", c: 59}},
            {k: "char", l: "2", s: "@", c: 3, fn: {l: "F2", c: 60}},
            {k: "char", l: "3", s: "#", c: 4, fn: {l: "F3", c: 61}},
            {k: "char", l: "4", s: "$", c: 5, fn: {l: "F4", c: 62}},
            {k: "char", l: "5", s: "%", c: 6, fn: {l: "F5", c: 63}},
            {k: "char", l: "6", s: "^", c: 7, fn: {l: "F6", c: 64}},
            {k: "char", l: "7", s: "&", c: 8, fn: {l: "F7", c: 65}},
            {k: "char", l: "8", s: "*", c: 9, fn: {l: "F8", c: 66}},
            {k: "char", l: "9", s: "(", c: 10, fn: {l: "F9", c: 67}},
            {k: "char", l: "0", s: ")", c: 11, fn: {l: "F10", c: 68}},
            {k: "char", l: "-", s: "_", c: 12, fn: {l: "F11", c: 87}},
            {k: "char", l: "=", s: "+", c: 13, fn: {l: "F12", c: 88}},
            {k: "key", l: "Backspace", c: 14, w: 2}
        ],
        // QWERTY
        [
            {k: "key", l: "Tab", c: 15, w: 1.5},
            {k: "char", l: "Q", c: 16}, {k: "char", l: "W", c: 17}, {k: "char", l: "E", c: 18},
            {k: "char", l: "R", c: 19}, {k: "char", l: "T", c: 20}, {k: "char", l: "Y", c: 21},
            {k: "char", l: "U", c: 22}, {k: "char", l: "I", c: 23}, {k: "char", l: "O", c: 24},
            {k: "char", l: "P", c: 25},
            {k: "char", l: "[", s: "{", c: 26}, {k: "char", l: "]", s: "}", c: 27},
            {k: "char", l: "\\", s: "|", c: 43, w: 1.5}
        ],
        // ASDF
        [
            {k: "key", l: "Caps Lock", c: 58, w: 1.75},
            {k: "char", l: "A", c: 30}, {k: "char", l: "S", c: 31}, {k: "char", l: "D", c: 32},
            {k: "char", l: "F", c: 33}, {k: "char", l: "G", c: 34}, {k: "char", l: "H", c: 35},
            {k: "char", l: "J", c: 36}, {k: "char", l: "K", c: 37}, {k: "char", l: "L", c: 38},
            {k: "char", l: ";", s: ":", c: 39}, {k: "char", l: "'", s: "\"", c: 40},
            {k: "key", l: "Enter", c: 28, w: 2.25, shift: {l: "Del", c: 111}}
        ],
        // ZXCV
        [
            {k: "shift", l: "Shift", w: 2.25},
            {k: "char", l: "Z", c: 44}, {k: "char", l: "X", c: 45}, {k: "char", l: "C", c: 46},
            {k: "char", l: "V", c: 47}, {k: "char", l: "B", c: 48}, {k: "char", l: "N", c: 49},
            {k: "char", l: "M", c: 50},
            {k: "char", l: ",", s: "<", c: 51}, {k: "char", l: ".", s: ">", c: 52},
            {k: "char", l: "/", s: "?", c: 53},
            {k: "shift", l: "Shift", w: 2.75}
        ],
        // 底行：Ctrl Win Alt 空格 Fn 表情 第二页
        [
            {k: "key", l: "Ctrl", c: 29, w: 1.25},
            {k: "key", l: "Win", c: 125, w: 1.25},
            {k: "key", l: "Alt", c: 56, w: 1.25},
            {k: "space", l: "", w: 6.25},
            {k: "fn", l: "Fn", w: 1.25},
            {k: "key", l: "", c: 127, w: 1.25, icon: "icons/context-menu.svg"},
            {k: "page", l: "", w: 1.25, to: "emoji", icon: "mood"},
            {k: "page", l: "", w: 1.25, to: "page2", icon: "layers"}
        ]
    ],

    // 表情 & 符号页：还没做。这里不画按键，只保留 4 行占位让键盘高度和主页面一致；
    // 返回键由卡片在左上角单独绘制（X），右上角槽在这里隐藏
    emoji: [
        [],
        [],
        [],
        [],
        []
    ],

    page2: [
        // 列布局（15 列）：
        //   空0 | 左区 1-4 | 空5 | 中区 6-8（正中） | 空9 | 右区 10-13 | 页面切换 14
        [
            {k: "spacer", l: "", w: 1},
            {k: "key", l: "Esc", c: 1}, {k: "key", l: "Print", c: 99},
            // ScrLk / Pause 在现代系统没用途，位置留空（保持 15 列不变形）
            {k: "spacer", l: "", w: 2},
            {k: "spacer", l: "", w: 1},
            {k: "key", l: "Ins", c: 110}, {k: "key", l: "Home", c: 102},
            {k: "key", l: "PgUp", c: 104},
            {k: "spacer", l: "", w: 1},
            {k: "key", l: "NumLk", c: 69}, {k: "key", l: "/", c: 98},
            {k: "key", l: "*", c: 55}, {k: "key", l: "-", c: 74},
            {k: "spacer", l: "", w: 1}
        ],
        [
            {k: "spacer", l: "", w: 1},
            {k: "spacer", l: "", w: 4},
            {k: "spacer", l: "", w: 1},
            {k: "key", l: "Del", c: 111}, {k: "key", l: "End", c: 107},
            {k: "key", l: "PgDn", c: 109},
            {k: "spacer", l: "", w: 1},
            {k: "key", l: "7", c: 71}, {k: "key", l: "8", c: 72},
            {k: "key", l: "9", c: 73}, {k: "key", l: "+", c: 78, rs: 2},
            {k: "spacer", l: "", w: 1}
        ],
        [
            {k: "spacer", l: "", w: 1},
            {k: "key", l: "F1", c: 59}, {k: "key", l: "F2", c: 60},
            {k: "key", l: "F3", c: 61}, {k: "key", l: "F4", c: 62},
            {k: "spacer", l: "", w: 1},
            {k: "spacer", l: "", w: 3},
            {k: "spacer", l: "", w: 1},
            {k: "key", l: "4", c: 75}, {k: "key", l: "5", c: 76},
            {k: "key", l: "6", c: 77},
            {k: "spacer", l: "", w: 1}
        ],
        [
            {k: "spacer", l: "", w: 1},
            {k: "key", l: "F5", c: 63}, {k: "key", l: "F6", c: 64},
            {k: "key", l: "F7", c: 65}, {k: "key", l: "F8", c: 66},
            {k: "spacer", l: "", w: 1},
            {k: "spacer", l: "", w: 1},
            {k: "key", l: "↑", c: 103},
            {k: "spacer", l: "", w: 1},
            {k: "spacer", l: "", w: 1},
            {k: "key", l: "1", c: 79}, {k: "key", l: "2", c: 80},
            {k: "key", l: "3", c: 81}, {k: "key", l: "Enter", c: 96, rs: 2},
            {k: "spacer", l: "", w: 1}
        ],
        [
            {k: "spacer", l: "", w: 1},
            {k: "key", l: "F9", c: 67}, {k: "key", l: "F10", c: 68},
            {k: "key", l: "F11", c: 87}, {k: "key", l: "F12", c: 88},
            {k: "spacer", l: "", w: 1},
            {k: "key", l: "←", c: 105}, {k: "key", l: "↓", c: 108},
            {k: "key", l: "→", c: 106},
            {k: "spacer", l: "", w: 1},
            {k: "key", l: "0", c: 82, w: 2}, {k: "key", l: ".", c: 83},
            {k: "page", l: "", to: "page1", icon: "layers", active: true}
        ]
    ]
}

function pageRows(page) {
    return rows[page] || rows.page1
}

// 把行数组摊平成 [{key, row, col, w, rs}]，处理跨行/跨列占位。
// QML 侧按 col*(unit+gap) / row*(keyH+gap) 绝对定位，跨行键高度按 rs 拉伸。
function layoutFlat(page) {
    var src = pageRows(page)
    var out = []
    var taken = {}
    for (var r = 0; r < src.length; r++) {
        var c = 0
        var row = src[r]
        for (var i = 0; i < row.length; i++) {
            while (taken[r + ":" + c]) c++
            var key = row[i]
            var w = key.w || 1
            var rs = key.rs || 1
            out.push({key: key, row: r, col: c, w: w, rs: rs})
            for (var dr = 0; dr < rs; dr++)
                for (var dc = 0; dc < w; dc++)
                    taken[(r + dr) + ":" + (c + dc)] = true
            c += w
        }
    }
    return out
}

// 假候选：候选栏先用这个显示，接入 fcitx5 后由真实候选替换
var demoCandidates = ["你好", "拟好", "你", "泥", "妮", "呢", "逆", "尼"]
var demoShortcuts = ["⇱", "⤢", "📌", "⤡", "📋", "⚙", "🚀", "🔈", "🔉", "🔇", "☀", "🌙"]
