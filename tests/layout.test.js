// layouts/phone.js 的单元测试：node --test tests/
//
// 布局文件是 QML 的 `.pragma library` 库，node 不能直接 require（第一行不是合法 JS），
// 所以这里去掉那行再求值。测的是**换页链路的数据侧**：
// 换页键（k: "page"）的 to 必须指向真实存在的页 —— 拆组件那次就是这类错没人挡，
// page 键的分发整条丢了，点了静默无反应。
const assert = require("node:assert");
const { test } = require("node:test");
const fs = require("node:fs");
const path = require("node:path");

function loadLayout() {
    const file = path.join(__dirname, "..", "layouts", "phone.js");
    const src = fs.readFileSync(file, "utf8").replace(/^\.pragma library\s*$/m, "");
    const mod = { exports: {} };
    new Function("module", "exports", src)(mod, mod.exports);
    return mod.exports;
}

const Layout = loadLayout();

test("layout: 换页键的 to 都指向真实页", () => {
    const pages = Object.keys(Layout.rows);
    assert.ok(pages.length >= 2, "至少要有主键区和第二页");
    for (const page of pages) {
        for (const entry of Layout.layoutFlat(page)) {
            if (entry.key.k !== "page")
                continue;
            assert.ok(entry.key.to, `${page} 里的换页键缺少 to`);
            assert.ok(pages.includes(entry.key.to),
                      `${page} 里的换页键指向不存在的页 "${entry.key.to}"`);
        }
    }
});

test("layout: 每一页都能从主键区走到，也能走回来", () => {
    const pages = Object.keys(Layout.rows);
    const targets = page => Layout.layoutFlat(page)
        .filter(e => e.key.k === "page")
        .map(e => e.key.to);
    for (const page of pages) {
        if (page === "page1")
            continue;
        // 有键位的页必须在布局里带一个回主键区的键；
        // emoji 是占位页（没有键位），返回靠卡片左上角那个 X，不走布局数据
        if (Layout.layoutFlat(page).length === 0)
            continue;
        assert.ok(targets(page).includes("page1"),
                  `页 ${page} 没有回主键区的换页键`);
    }
    for (const page of pages) {
        if (page === "page1")
            continue;
        assert.ok(targets("page1").includes(page),
                  `主键区没有到 ${page} 的换页键`);
    }
});

test("layout: 摊平后的键位不互相覆盖", () => {
    for (const page of Object.keys(Layout.rows)) {
        const taken = new Set();
        for (const entry of Layout.layoutFlat(page)) {
            for (let dr = 0; dr < entry.rs; dr++) {
                for (let dc = 0; dc < entry.w; dc++) {
                    const cell = `${entry.row + dr}:${entry.col + dc}`;
                    assert.ok(!taken.has(cell), `${page} 的 ${cell} 被两个键占了`);
                    taken.add(cell);
                }
            }
        }
    }
});

test("两页的翻页键宽度一致（否则切页时那颗键会变窄）", () => {
    const widths = {};
    for (const page of ["page1", "page2"]) {
        for (const entry of Layout.layoutFlat(page)) {
            const key = entry.key;
            if (key && key.k === "page" && key.icon === "layers")
                widths[page] = key.w === undefined ? 1 : key.w;
        }
    }
    assert.ok(widths.page1 !== undefined, "page1 应有 layers 翻页键");
    assert.ok(widths.page2 !== undefined, "page2 应有 layers 翻页键");
    assert.equal(widths.page2, widths.page1,
                 "page2 翻页键宽 " + widths.page2 + " 与 page1 的 " + widths.page1 + " 不一致");
});

test("所有 pageRows 的字面量参数都是真实页名", () => {
    // pageRows 对未知页名静默回落到 page1，写错一个字都看不出来
    // （踩过：mainArea 用了 Layout.pageRows("keys")，一直拿到主键区的行数）
    const valid = Object.keys(Layout.rows);
    const files = ["../KeyboardCard.qml", "../KeyboardMetrics.qml",
                   "../KeyboardWindow.qml", "../FloatingKeyboardWindow.qml"];
    const bad = [];
    for (const rel of files) {
        const abs = path.join(__dirname, rel);
        if (!fs.existsSync(abs))
            continue;
        const src = fs.readFileSync(abs, "utf8");
        // 只查字符串字面量调用；传变量的那种（pageRows(page)）由页名白名单保证
        const re = /pageRows\(\s*(["'])([^"']+)\1\s*\)/g;
        let m;
        while ((m = re.exec(src)) !== null) {
            const name = m[2];
            if (valid.indexOf(name) < 0)
                bad.push(rel + " 里的 pageRows(\"" + name + "\")");
        }
    }
    assert.deepEqual(bad, [], "存在不合法的页名：" + bad.join(", "));
});
