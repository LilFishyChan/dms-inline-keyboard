// modifiers.js 的单元测试：node --test tests/
const assert = require("node:assert");
const { test } = require("node:test");
const {
    MODES,
    DEFAULT_MODE,
    DEFAULT_DOUBLE_TAP_MS,
    modifierNameFor,
    nextModifierState,
    pressModifierState,
    releaseModifierState,
    clearTransient
} = require("../modifiers.js");

// 点一下：只关心「点完是什么状态」
const tap = (name, current, mode, extra) =>
    nextModifierState(Object.assign({ name, current, mode }, extra || {}));

test("modifierNameFor: shift 键", () => {
    assert.equal(modifierNameFor({ k: "shift" }), "shift");
});

test("modifierNameFor: 按 keycode 认 caps / ctrl / alt / super", () => {
    assert.equal(modifierNameFor({ k: "key", c: 58 }), "caps");
    assert.equal(modifierNameFor({ k: "key", c: 29 }), "ctrl");
    assert.equal(modifierNameFor({ k: "key", c: 56 }), "alt");
    assert.equal(modifierNameFor({ k: "key", c: 125 }), "super");
});

test("modifierNameFor: 普通键 / 空值返回空串", () => {
    assert.equal(modifierNameFor({ k: "char", c: 30 }), "");
    assert.equal(modifierNameFor({ k: "space" }), "");
    assert.equal(modifierNameFor(null), "");
    assert.equal(modifierNameFor(undefined), "");
});

test("默认模式是双击锁定，双击间隔 300ms", () => {
    assert.equal(DEFAULT_MODE, MODES.doubleTapLock);
    assert.equal(DEFAULT_DOUBLE_TAP_MS, 300);
});

// ---------------- noLock：按住才生效 ----------------
test("noLock: 点一下不留状态", () => {
    assert.equal(tap("shift", 0, MODES.noLock), 0);
    assert.equal(tap("shift", 1, MODES.noLock), 1, "点按不改按住中的状态");
});

test("noLock: 按下 → 1，松开 → 0", () => {
    assert.equal(pressModifierState(MODES.noLock, 0), 1);
    assert.equal(releaseModifierState(MODES.noLock, 1), 0);
});

test("其它模式下按/松不影响状态", () => {
    for (const m of [MODES.toggle, MODES.tapLock, MODES.doubleTapLock]) {
        assert.equal(pressModifierState(m, 0), 0, m);
        assert.equal(releaseModifierState(m, 2), 2, m);
    }
});

// ---------------- toggle：点一下激活，按普通键取消 ----------------
test("toggle: 0 → 1 → 0", () => {
    assert.equal(tap("ctrl", 0, MODES.toggle), 1);
    assert.equal(tap("ctrl", 1, MODES.toggle), 0);
    assert.equal(tap("ctrl", 2, MODES.toggle), 0, "残留锁定也回未激活");
});

// ---------------- tapLock：点一下锁定，只有再点本键取消 ----------------
test("tapLock: 0 → 2 → 0", () => {
    assert.equal(tap("alt", 0, MODES.tapLock), 2);
    assert.equal(tap("alt", 2, MODES.tapLock), 0);
});

// ---------------- doubleTapLock：单击 = toggle，双击 = 锁定 ----------------
test("doubleTapLock: 单击进入软激活（同 toggle）", () => {
    assert.equal(tap("shift", 0, MODES.doubleTapLock), 1);
});

test("doubleTapLock: 300ms 内再点同键 → 锁定", () => {
    assert.equal(tap("shift", 1, MODES.doubleTapLock,
        { isSameKey: true, sinceLastTapMs: 120 }), 2);
});

test("doubleTapLock: 双击间隔边界", () => {
    assert.equal(tap("shift", 1, MODES.doubleTapLock,
        { isSameKey: true, sinceLastTapMs: 299 }), 2, "299ms 仍算双击");
    assert.equal(tap("shift", 1, MODES.doubleTapLock,
        { isSameKey: true, sinceLastTapMs: 300 }), 0, "恰好 300ms 算超时");
});

test("doubleTapLock: 换另一个修饰键再点不算双击", () => {
    assert.equal(tap("ctrl", 1, MODES.doubleTapLock,
        { isSameKey: false, sinceLastTapMs: 50 }), 0);
});

test("doubleTapLock: 锁定后再点解除", () => {
    assert.equal(tap("shift", 2, MODES.doubleTapLock), 0);
});

test("doubleTapLock: 自定义双击间隔", () => {
    assert.equal(tap("shift", 1, MODES.doubleTapLock,
        { isSameKey: true, sinceLastTapMs: 500, doubleTapMs: 600 }), 2);
});

// ---------------- caps lock 不受模式影响 ----------------
test("caps lock: 任何模式下点击都是 0 ⇄ 2", () => {
    for (const m of Object.values(MODES)) {
        assert.equal(tap("caps", 0, m), 2, m);
        assert.equal(tap("caps", 2, m), 0, m);
    }
});

test("nextModifierState: 非法输入当作未激活", () => {
    assert.equal(tap("shift", undefined, MODES.doubleTapLock), 1);
    assert.equal(tap("shift", 99, MODES.doubleTapLock), 1);
});

test("nextModifierState: 未知模式退回默认双击锁定", () => {
    assert.equal(tap("shift", 0, "noSuchMode"), 1);
    assert.equal(tap("shift", 1, "noSuchMode",
        { isSameKey: true, sinceLastTapMs: 100 }), 2);
});

// ---------------- 普通键按下后的复位 ----------------
test("clearTransient: 软激活(1)清零，锁定(2)保留", () => {
    assert.deepEqual(
        clearTransient({ shift: 1, ctrl: 2, alt: 0 }),
        { shift: 0, ctrl: 2, alt: 0 });
});

test("clearTransient: caps lock 永远保留", () => {
    assert.equal(clearTransient({ caps: 2 }).caps, 2);
});

test("clearTransient: 不修改入参", () => {
    const input = { shift: 1 };
    clearTransient(input);
    assert.equal(input.shift, 1);
});

test("modifierNameFor: Fn 键也识别成修饰键", () => {
    assert.equal(modifierNameFor({ k: "fn" }), "fn");
});

test("nextModifierState: Fn 在 noLock 模式下退化成开关（点一下锁住）", () => {
    const opts = (current) => ({ name: "fn", current: current, mode: MODES.noLock });
    assert.equal(nextModifierState(opts(0)), 2);
    assert.equal(nextModifierState(opts(2)), 0);
});

test("nextModifierState: Fn 在双击锁定模式下 0 → 1 → 2 → 0", () => {
    const t = (current, same, ms) => nextModifierState({
        name: "fn", current: current, mode: MODES.doubleTapLock,
        isSameKey: same, sinceLastTapMs: ms, doubleTapMs: 300
    });
    assert.equal(t(0, false, -1), 1);
    assert.equal(t(1, true, 120), 2);
    assert.equal(t(2, false, -1), 0);
});

test("clearTransient: Fn 的一次性状态会被普通键清掉，锁定的保留", () => {
    assert.deepEqual(clearTransient({ fn: 1 }).fn, 0);
    assert.deepEqual(clearTransient({ fn: 2 }).fn, 2);
});
