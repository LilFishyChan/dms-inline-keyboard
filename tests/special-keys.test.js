// layouts/special-keys.js 的单元测试：node --test tests/
//
// 测的是「特殊键该画图标还是文字」这个纯决策。它错了的表现很具体：
// 键帽上出现空图标（选图标但没这个图标）、或者 Win 键没跟着自己的设置走。
const assert = require("node:assert");
const { test } = require("node:test");
const fs = require("node:fs");
const path = require("node:path");

function loadModule(name) {
    const file = path.join(__dirname, "..", "layouts", name);
    const src = fs.readFileSync(file, "utf8").replace(/^\.pragma library\s*$/m, "");
    const mod = { exports: {} };
    new Function("module", "exports", src)(mod, mod.exports);
    return mod.exports;
}

const SK = loadModule("special-keys.js");

test("special-keys: 普通字符键原样返回", () => {
    for (const label of ["a", "1", "~", "中文"]) {
        const got = SK.resolve(label, "icon", "mod");
        assert.deepEqual(got, { icon: "", text: label });
    }
});

test("special-keys: 空标签不崩", () => {
    assert.deepEqual(SK.resolve("", "full", "mod"), { icon: "", text: "" });
    assert.deepEqual(SK.resolve(null, "full", "mod"), { icon: "", text: "" });
    assert.deepEqual(SK.resolve(undefined, "short", "mod"), { icon: "", text: "" });
});

test("special-keys: 完整形态用全名", () => {
    assert.equal(SK.resolve("Backspace", "full", "mod").text, "Backspace");
    assert.equal(SK.resolve("Caps Lock", "full", "mod").text, "Caps Lock");
    // 完整形态不画图标
    assert.equal(SK.resolve("Enter", "full", "mod").icon, "");
});

test("special-keys: 简写形态用文字，不用 ⌫ ↵ ⇧ 这类符号", () => {
    assert.equal(SK.resolve("Backspace", "short", "mod").text, "Back");
    assert.equal(SK.resolve("Enter", "short", "mod").text, "Enter");
    assert.equal(SK.resolve("Shift", "short", "mod").text, "Shift");
    assert.equal(SK.resolve("Caps Lock", "short", "mod").text, "Caps");
    // 简写一律非空，且不含符号字符
    for (const name of ["Backspace", "Enter", "Shift", "Tab", "Caps Lock", "Del",
                        "Ins", "Home", "End", "PgUp", "PgDn", "Print", "NumLk"]) {
        const t = SK.resolve(name, "short", "mod").text;
        assert.ok(t && t.length > 0, name + " 的简写不能为空");
        assert.ok(!/[⌫↵⇧⌦⇪]/.test(t), name + " 的简写不应含符号: " + t);
        assert.ok(!/[\u4e00-\u9fa5]/.test(t), name + " 的简写不应含中文: " + t);
    }
});

test("special-keys: 图标形态返回图标名、文字为空", () => {
    const got = SK.resolve("Backspace", "icon", "mod");
    assert.equal(got.icon, "backspace");
    assert.equal(got.text, "");
});

test("special-keys: Del 没有图标，图标形态回落成文字", () => {
    // 原来写的 "backspace_outline" 不是字体里的连字（只有 backspace），
    // 图标形态下画不出字形 → 空键帽。Del 也不需要垃圾桶之类的图标，
    // 直接不配图标，按「该键没有图标」的通用规则回落成短名。
    const got = SK.resolve("Del", "icon", "mod");
    assert.equal(got.icon, "");
    assert.equal(got.text, "Del");
});

test("special-keys: 选图标但该键没有图标时回落到缩写", () => {
    // Ctrl 没有合适的 Material 图标，不能留空键帽
    const got = SK.resolve("Ctrl", "icon", "mod");
    assert.equal(got.icon, "");
    assert.equal(got.text, "Ctrl");
});

test("special-keys: Win 默认是 Mod 文字", () => {
    for (const style of ["icon", "short", "full"]) {
        const got = SK.resolve("Win", style, "mod");
        assert.equal(got.text, "Mod", "style=" + style + " 时 Win 仍应是 Mod");
        assert.equal(got.icon, "");
    }
});

test("special-keys: Win 的文字形态与图标形态", () => {
    assert.equal(SK.resolve("Win", "full", "mod").text, "Mod");
    assert.equal(SK.resolve("Win", "full", "super").text, "Super");
    assert.equal(SK.resolve("Win", "full", "system").icon, "keyboard_command_key");
    // 自定义图标：传什么用什么
    assert.equal(SK.resolve("Win", "full", "custom", "window").icon, "window");
    // 没传自定义图标时退回 Mod 文字，不留空键帽
    const fallback = SK.resolve("Win", "full", "custom", "");
    assert.equal(fallback.icon, "");
    assert.equal(fallback.text, "Mod");
});

test("special-keys: 未知 winLook 回落到 mod", () => {
    assert.equal(SK.resolve("Win", "full", "nonsense").text, "Mod");
    assert.equal(SK.resolve("Win", "full", "").text, "Mod");
});

test("special-keys: isSpecialKey 只认表里的键和 Win", () => {
    assert.equal(SK.isSpecialKey("Backspace"), true);
    assert.equal(SK.isSpecialKey("Win"), true);
    assert.equal(SK.isSpecialKey("Caps Lock"), true);
    assert.equal(SK.isSpecialKey("a"), false);
    assert.equal(SK.isSpecialKey(""), false);
    assert.equal(SK.isSpecialKey("toString"), false, "不能把原型上的名字当特殊键");
});

test("special-keys: 未知特殊键按普通文字透传", () => {
    const got = SK.resolve("F13", "icon", "mod");
    assert.deepEqual(got, { icon: "", text: "F13" });
});

test("special-keys: 归一化非法设置值", () => {
    assert.equal(SK.normalizeStyle("icon"), "icon");
    assert.equal(SK.normalizeStyle("garbage"), "full");
    assert.equal(SK.normalizeStyle(undefined), "full");
    // "windows" 已移除，老配置迁移到 system
    assert.equal(SK.normalizeWinLook("windows"), "system");
    assert.equal(SK.normalizeWinLook("super"), "super");
    assert.equal(SK.normalizeWinLook("custom"), "custom");
    assert.equal(SK.normalizeWinLook("garbage"), "mod");
});

test("special-keys: 布局里用到的特殊键都在表里", () => {
    // 布局新增一个特殊键却没登记，选「图标」形态时会退化成全名字——
    // 这条钉住「布局里出现的都认识」
    const Layout = loadModule("phone.js");
    const known = new Set(Object.keys(SK.SPECIAL_KEYS).concat(["Win"]));
    const missing = new Set();
    for (const page of Object.keys(Layout.rows)) {
        for (const row of Layout.rows[page]) {
            for (const key of row) {
                const label = key && key.l;
                if (!label)
                    continue;
                // 只关心「完整名字有多字母」的键，单字符和数字跳过
                if (/^[A-Za-z ]+$/.test(label) && label.length > 2 && !known.has(label))
                    missing.add(label);
            }
        }
    }
    assert.deepEqual([...missing], [], "这些键没在 SPECIAL_KEYS 里登记");
});
