// candidates.js 的单元测试：node --test tests/
// 守两件事：① 每个词都放得下（等分压窄 = 截断文字）② 每行右边界贴住可用宽度。
const assert = require("node:assert");
const { test } = require("node:test");
const { layoutCandidates } = require("../candidates.js");

// 假测宽：一个字符 20px
const measure = (t) => String(t).length * 20;
const opts = { availW: 300, gap: 6, rowH: 40, pad: 30 };

const sumWidth = (cells) => cells.reduce((s, c) => s + c.w, 0);
const rightEdge = (cells, gap) => cells[cells.length - 1].x + cells[cells.length - 1].w;

test("candidates: 空列表返回空布局", () => {
    const laid = layoutCandidates([], measure, opts);
    assert.deepEqual(laid.rows, []);
    assert.deepEqual(laid.items, []);
    assert.equal(laid.contentH, 0);
});

test("candidates: 每格都不窄于文字宽 + padding（不被压窄）", () => {
    const list = ["一", "二", "三", "四"].map((t, i) => ({ i, t }));
    const laid = layoutCandidates(list, measure, opts);
    for (const row of laid.rows)
        for (const cell of row)
            assert.ok(cell.w >= Math.ceil(measure(cell.t) + opts.pad),
                      `${cell.t} 被压窄: ${cell.w} < ${Math.ceil(measure(cell.t) + opts.pad)}`);
});

test("candidates: 每行右边界贴住 availW", () => {
    const list = ["一", "二", "三", "四", "五"].map((t, i) => ({ i, t }));
    const laid = layoutCandidates(list, measure, opts);
    for (const row of laid.rows)
        assert.equal(rightEdge(row, opts.gap), opts.availW);
});

test("candidates: 行内间距是 gap，格子从 0 开始依次排", () => {
    const list = ["一", "二", "三"].map((t, i) => ({ i, t }));
    const row = layoutCandidates(list, measure, opts).rows[0];
    assert.equal(row[0].x, 0);
    for (let i = 1; i < row.length; i++)
        assert.equal(row[i].x, row[i - 1].x + row[i - 1].w + opts.gap);
});

test("candidates: 超长词独占一行并被钳到 availW", () => {
    const long = "一二三四五六七八九十一二三四五六七八九十"; // 20 字 = 400 + 30
    const laid = layoutCandidates([{ i: 0, t: long }, { i: 1, t: "短" }], measure, opts);
    assert.equal(laid.rows.length, 2);
    assert.equal(laid.rows[0].length, 1);
    assert.equal(laid.rows[0][0].w, opts.availW);
});

test("candidates: 每行最后一项不画分隔线，其余要画", () => {
    const list = ["一", "二", "三"].map((t, i) => ({ i, t }));
    const row = layoutCandidates(list, measure, opts).rows[0];
    assert.equal(row[row.length - 1].sep, false);
    for (let i = 0; i < row.length - 1; i++)
        assert.equal(row[i].sep, true);
});

test("candidates: 内容高按行数算，不含多余行间距", () => {
    const one = layoutCandidates([{ i: 0, t: "一" }], measure, opts);
    assert.equal(one.contentH, opts.rowH);

    // 两行：rowH + gap + rowH
    const long = "一二三四五六七八九十一二三四五六七八九十";
    const two = layoutCandidates([{ i: 0, t: long }, { i: 1, t: "短" }], measure, opts);
    assert.equal(two.contentH, opts.rowH * 2 + opts.gap);
});

test("candidates: items 是 rows 的扁平视图（同一批对象）", () => {
    const list = ["一", "二", "三"].map((t, i) => ({ i, t }));
    const laid = layoutCandidates(list, measure, opts);
    assert.equal(laid.items.length, list.length);
    assert.equal(laid.items[0], laid.rows[0][0]);
});

test("candidates: 原始下标跟数据走，不被显示顺序改写", () => {
    const list = [{ i: 7, t: "一" }, { i: 3, t: "二" }];
    const laid = layoutCandidates(list, measure, opts);
    assert.deepEqual(laid.items.map((c) => c.i), [7, 3]);
});

test("candidates: 没有 measure / 空文字时不崩", () => {
    const laid = layoutCandidates([{ i: 0, t: "" }, { i: 1, t: "x" }], null, opts);
    assert.equal(laid.items.length, 2);
    assert.ok(laid.rows.length >= 1);
});
