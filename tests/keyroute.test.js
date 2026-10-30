// keyroute.js 的单元测试：node --test tests/
// 守的是「哪些键交给输入法」这条判据 —— 判错不会报错，只会静默失效。
const assert = require("node:assert");
const { test } = require("node:test");
const { ROUTE, producesText, decideRoute } = require("../keyroute.js");

// 常用状态：中文输入法、无预编辑
const zh = { available: true, preedit: "", imKeyboard: false, isAsciiMode: false, combo: false };
const withPreedit = Object.assign({}, zh, { preedit: "ni" });

test("keyroute: 字母和符号交给输入法", () => {
    assert.equal(decideRoute("a", "char", zh), ROUTE.fcitx);
    assert.equal(decideRoute("A", "char", zh), ROUTE.fcitx);
    assert.equal(decideRoute(",", "char", zh), ROUTE.fcitx);
    assert.equal(decideRoute("!", "char", zh), ROUTE.fcitx);
    assert.equal(decideRoute("~", "char", zh), ROUTE.fcitx);
});

test("keyroute: 数字交给合成器（rime 会当候选序号）", () => {
    for (const d of ["0", "1", "5", "9"]) {
        assert.equal(decideRoute(d, "char", zh), ROUTE.ydotool, d);
        assert.equal(decideRoute(d, "key", zh), ROUTE.ydotool, "小键盘 " + d);
    }
});

test("keyroute: 空格交给输入法（负责上屏候选）", () => {
    assert.equal(decideRoute("space", "space", zh), ROUTE.fcitx);
});

test("keyroute: 无预编辑时的回车/退格必须发真键", () => {
    assert.equal(decideRoute("Enter", "key", zh), ROUTE.ydotool);
    assert.equal(decideRoute("Backspace", "key", zh), ROUTE.ydotool);
    // 小键盘回车同理
    assert.equal(decideRoute("Enter", "key", zh), ROUTE.ydotool);
});

test("keyroute: 有预编辑时的回车/退格交给输入法（上屏、删字）", () => {
    assert.equal(decideRoute("Enter", "key", withPreedit), ROUTE.fcitx);
    assert.equal(decideRoute("Backspace", "key", withPreedit), ROUTE.fcitx);
});

test("keyroute: 控制键一律发真键", () => {
    const keys = ["Tab", "Esc", "Del", "F1", "F12", "Home", "End", "PgUp", "PgDn",
                  "Ins", "Print", "NumLk", "↑", "↓", "←", "→"];
    for (const k of keys)
        assert.equal(decideRoute(k, "key", zh), ROUTE.ydotool, k);
});

test("keyroute: 小键盘符号不过输入法（否则被转成中文标点）", () => {
    for (const s of ["*", "-", "+", "/", "."])
        assert.equal(decideRoute(s, "key", zh), ROUTE.ydotool, "小键盘 " + s);
});

test("keyroute: 英文模式下全部发真键", () => {
    const ascii = Object.assign({}, zh, { isAsciiMode: true });
    assert.equal(decideRoute("a", "char", ascii), ROUTE.ydotool);
    assert.equal(decideRoute("space", "space", ascii), ROUTE.ydotool);
});

test("keyroute: 纯键盘布局（无候选能力）全部发真键", () => {
    const kb = Object.assign({}, zh, { imKeyboard: true });
    assert.equal(decideRoute("a", "char", kb), ROUTE.ydotool);
});

test("keyroute: 组合键优先于输入法（Ctrl+C 不能按两次）", () => {
    const combo = Object.assign({}, zh, { combo: true });
    assert.equal(decideRoute("c", "char", combo), ROUTE.ydotool);
});

test("keyroute: 输入法不可用时退化成真键", () => {
    const noBridge = Object.assign({}, zh, { available: false });
    assert.equal(decideRoute("a", "char", noBridge), ROUTE.ydotool);
});

test("keyroute: 空键名 / 空状态不崩", () => {
    assert.equal(decideRoute("", "char", zh), ROUTE.ydotool);
    assert.equal(decideRoute(null, "char", zh), ROUTE.ydotool);
    assert.equal(decideRoute("a", "char", null), ROUTE.fcitx);
});

test("producesText: 非 ASCII 的标签不算会产生文本", () => {
    assert.equal(producesText("↑", "key", zh), false);
    assert.equal(producesText("万", "char", zh), false);
});
