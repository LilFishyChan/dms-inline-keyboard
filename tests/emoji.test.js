// layouts/emoji.js 的单元测试：node --test tests/
//
// 这个文件是 tools/gen-emoji.py 生成的，测试主要守住**上屏协议**的硬约束：
// text: 是一行一条消息，字符里带换行就会把一条消息劈成两条；
// 另外分组不能重复、不能和表情重叠，否则界面上同一个字符出现两次。
const assert = require("node:assert");
const { test } = require("node:test");
const fs = require("node:fs");
const path = require("node:path");

function loadEmoji() {
    const file = path.join(__dirname, "..", "layouts", "emoji.js");
    const src = fs.readFileSync(file, "utf8").replace(/^\.pragma library\s*$/m, "");
    const mod = { exports: {} };
    new Function("module", "exports", src)(mod, mod.exports);
    return mod.exports;
}

const Emoji = loadEmoji();
const EMOJI = Emoji.emojiGroups;
const SYMBOLS = Emoji.symbolGroups;

function items(groups) {
    const out = [];
    for (const g of groups)
        for (const ch of g["items"])
            out.push(ch);
    return out;
}

test("emoji: 九个官方分组都在，且都不为空", () => {
    assert.deepEqual(EMOJI.map(g => g.id), [
        "smileys", "people", "nature", "food", "travel",
        "activities", "objects", "symbols", "flags",
    ]);
    for (const g of EMOJI)
        assert.ok(g["items"].length > 0, `${g.id} 分组是空的`);
    // Unicode 16 的基础表情集约 1900 个（不含肤色变体），留一点余量
    const total = items(EMOJI).length;
    assert.ok(total > 1800 && total < 2100, `表情总数异常: ${total}`);
});

test("emoji: 不含肤色变体，也没有重复", () => {
    const seen = new Set();
    for (const ch of items(EMOJI)) {
        for (const c of ch) {
            const cp = c.codePointAt(0);
            assert.ok(cp < 0x1F3FB || cp > 0x1F3FF, `混进了肤色变体: ${ch}`);
        }
        assert.ok(!seen.has(ch), `重复的表情: ${ch}`);
        seen.add(ch);
    }
});

test("符号: 和表情不重叠，也没有控制字符", () => {
    const emojiSet = new Set(items(EMOJI));
    const seen = new Set();
    for (const ch of items(SYMBOLS)) {
        assert.ok(!emojiSet.has(ch), `符号页里出现了表情: ${ch}`);
        assert.ok(!seen.has(ch), `重复的符号: ${ch}（分组之间也要去重）`);
        seen.add(ch);
        const cp = ch.codePointAt(0);
        assert.ok(cp > 0x20 && cp !== 0x7F, `控制字符混进来了: ${cp.toString(16)}`);
    }
});

test("上屏协议: 没有字符带换行或回车", () => {
    // text:<utf8> 是按 \n 切行的，一条消息里出现换行就会被劈成两条
    for (const ch of items(EMOJI).concat(items(SYMBOLS)))
        assert.ok(!/[\n\r]/.test(ch), `含换行的字符: ${JSON.stringify(ch)}`);
});

test("flatten: 全部 = 各分组顺次拼接", () => {
    const flat = Emoji.flatten(EMOJI);
    assert.equal(flat.length, items(EMOJI).length);
    assert.equal(flat[0], EMOJI[0]["items"][0]);
    assert.equal(flat[flat.length - 1],
                 EMOJI[EMOJI.length - 1]["items"].slice(-1)[0]);
});
