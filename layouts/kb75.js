.pragma library

// 75% 配列（ANSI，16 单位 × 6 行，84 键）—— 对应 QMK 的 LAYOUT_75_ansi 键序。
//
// 和 phone.js 的差别：
//   - 行宽 16 单位（比主键区的 15 多出右侧那一列导航键）
//   - F 区、导航列、方向键全部常驻，一页放完，没有 page2
//   - 底行 16 单位被修饰键 + 方向键占满，没有表情键和换页键
//     （表情走内置动作，见 actions.js 的 emoji）
//   - Fn 键这次不做，等 fn 层的映射定下来再加：把底行的空格从 6.75 缩到 6.25、
//     在 Alt 和 Ctrl 之间插一个 1 单位的 `{k: "fn", l: "Fn", w: 1}` 就正好填满 16
//
// 键字段和 phone.js 一致：k kind / l 下档 / s 上档 / c keycode / w 宽度 / rs 跨行

var rowUnits = 16

var rows = {
    page1: [
        // F 区：Esc + F1–F12 + PrtSc / Pause / Del（QMK 75_ansi 的 16 键满行）
        [
            {k: "key", l: "Esc", c: 1},
            {k: "key", l: "F1", c: 59}, {k: "key", l: "F2", c: 60},
            {k: "key", l: "F3", c: 61}, {k: "key", l: "F4", c: 62},
            {k: "key", l: "F5", c: 63}, {k: "key", l: "F6", c: 64},
            {k: "key", l: "F7", c: 65}, {k: "key", l: "F8", c: 66},
            {k: "key", l: "F9", c: 67}, {k: "key", l: "F10", c: 68},
            {k: "key", l: "F11", c: 87}, {k: "key", l: "F12", c: 88},
            {k: "key", l: "PrtSc", c: 99}, {k: "key", l: "Pause", c: 119},
            {k: "key", l: "Del", c: 111}
        ],
        // 数字行 + 右列 Home
        [
            {k: "char", l: "`", s: "~", c: 41},
            {k: "char", l: "1", s: "!", c: 2}, {k: "char", l: "2", s: "@", c: 3},
            {k: "char", l: "3", s: "#", c: 4}, {k: "char", l: "4", s: "$", c: 5},
            {k: "char", l: "5", s: "%", c: 6}, {k: "char", l: "6", s: "^", c: 7},
            {k: "char", l: "7", s: "&", c: 8}, {k: "char", l: "8", s: "*", c: 9},
            {k: "char", l: "9", s: "(", c: 10}, {k: "char", l: "0", s: ")", c: 11},
            {k: "char", l: "-", s: "_", c: 12}, {k: "char", l: "=", s: "+", c: 13},
            {k: "key", l: "Backspace", c: 14, w: 2, shift: {l: "Del", c: 111}},
            {k: "key", l: "Home", c: 102}
        ],
        // QWERTY + 右列 PgUp
        [
            {k: "key", l: "Tab", c: 15, w: 1.5},
            {k: "char", l: "Q", c: 16}, {k: "char", l: "W", c: 17}, {k: "char", l: "E", c: 18},
            {k: "char", l: "R", c: 19}, {k: "char", l: "T", c: 20}, {k: "char", l: "Y", c: 21},
            {k: "char", l: "U", c: 22}, {k: "char", l: "I", c: 23}, {k: "char", l: "O", c: 24},
            {k: "char", l: "P", c: 25},
            {k: "char", l: "[", s: "{", c: 26}, {k: "char", l: "]", s: "}", c: 27},
            {k: "char", l: "\\", s: "|", c: 43, w: 1.5},
            {k: "key", l: "PgUp", c: 104}
        ],
        // ASDF + 右列 PgDn
        [
            {k: "key", l: "Caps Lock", c: 58, w: 1.75},
            {k: "char", l: "A", c: 30}, {k: "char", l: "S", c: 31}, {k: "char", l: "D", c: 32},
            {k: "char", l: "F", c: 33}, {k: "char", l: "G", c: 34}, {k: "char", l: "H", c: 35},
            {k: "char", l: "J", c: 36}, {k: "char", l: "K", c: 37}, {k: "char", l: "L", c: 38},
            {k: "char", l: ";", s: ":", c: 39}, {k: "char", l: "'", s: "\"", c: 40},
            {k: "key", l: "Enter", c: 28, w: 2.25},
            {k: "key", l: "PgDn", c: 109}
        ],
        // ZXCV + ↑ / End
        [
            {k: "shift", l: "Shift", w: 2.25},
            {k: "char", l: "Z", c: 44}, {k: "char", l: "X", c: 45}, {k: "char", l: "C", c: 46},
            {k: "char", l: "V", c: 47}, {k: "char", l: "B", c: 48}, {k: "char", l: "N", c: 49},
            {k: "char", l: "M", c: 50},
            {k: "char", l: ",", s: "<", c: 51}, {k: "char", l: ".", s: ">", c: 52},
            {k: "char", l: "/", s: "?", c: 53},
            {k: "shift", l: "Shift", w: 1.75},
            {k: "key", l: "↑", c: 103},
            {k: "key", l: "End", c: 107}
        ],
        // 底行：Ctrl Win Alt 空格 Alt 菜单 Ctrl + 方向键（16 单位正好排满）
        // 没有表情键、没有换页键；Fn 以后再插
        [
            {k: "key", l: "Ctrl", c: 29, w: 1.25},
            {k: "key", l: "Win", c: 125, w: 1.25},
            {k: "key", l: "Alt", c: 56, w: 1.25},
            {k: "space", l: "", w: 5.75},
            {k: "key", l: "Alt", c: 56, w: 1.25},
            // 菜单位置照物理键盘：右 Alt 和右 Ctrl 之间；
            // 空格从 6.75 收到 5.75 才腾得出来
            {k: "key", l: "", c: 127, w: 1, icon: "icons/context-menu.svg"},
            {k: "key", l: "Ctrl", c: 29, w: 1.25},
            {k: "key", l: "←", c: 105},
            {k: "key", l: "↓", c: 108},
            {k: "key", l: "→", c: 106}
        ]
    ]
}

function pageRows(page) {
    return rows[page] || rows.page1
}

// 把行数组摊平成 [{key, row, col, w, rs}]，处理跨行/跨列占位。
// QML 侧按 col*(unit+gap) / row*(keyH+gap) 绝对定位，跨行键高度按 rs 拉伸。
function layoutFlat(page, overrideRows) {
    var src = overrideRows || pageRows(page)
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

// node --test 用（QML 里没有 module，这段不会执行）
if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        rows: rows,
        rowUnits: rowUnits,
        pageRows: pageRows,
        layoutFlat: layoutFlat
    }
}
