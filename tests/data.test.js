// data.js 的单元测试：node --test tests/
//
// 这一层是「数据功能层」：addon 写出的 JSON → 键盘内部模型。
// 全部用纯函数验证，不需要启动 fcitx5、不需要装 addon，
// 所以改完数据映射立刻能确认有没有把字段接错。
//
// fixtures 里的样本是从真实 addon 输出里抄下来的，不是手编的理想值——
// 这样能挡住「字段名改了但测试还是绿的」。
const assert = require("node:assert");
const { test } = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const {
    emptyStatus, cloneStatus, parseStatus, parseImList, isAsciiMode,
    buildImRows, nextImRow, expandedCandidates, barCandidates,
    swapEscTilde, actionExists, quickBarIndexFor,
} = require("../data.js");

const fixture = name =>
    fs.readFileSync(path.join(__dirname, "fixtures", name), "utf8");

const STATUS_CN = () => fixture("status-rime-cn.json");
const IMLIST = () => fixture("imlist.json");

// ---------------- parseStatus ----------------

test("parseStatus: 真实 rime 中文样本", () => {
    const s = parseStatus(STATUS_CN(), null);
    assert.deepEqual(s.items, ["你好", "拟好", "泥蒿", "你", "泥", "尼"]);
    assert.equal(s.im, "rime");
    assert.equal(s.imLabel, "万");
    assert.equal(s.keyboard, false, "rime 不是纯键盘布局");
    assert.equal(s.hasNext, true);
    assert.equal(s.hasPrev, false);
    assert.ok(s.imIcon.endsWith("fcitx-rime.png"));
});

test("parseStatus: 序号不混进候选词", () => {
    const s = parseStatus(STATUS_CN(), null);
    // 顶栏不能显示 "1 你好" 这种带序号的候选
    assert.ok(!s.items.some(t => /^\d/.test(t)));
});

test("parseStatus: 非法 JSON 保留上一次的值", () => {
    const prev = parseStatus(STATUS_CN(), null);
    // addon 是 tmp+rename 原子写，但读到半截仍有可能
    const got = parseStatus('{"items":["半截', prev);
    assert.deepEqual(got, prev, "解析失败必须原样返回 prev");
    assert.notStrictEqual(got, prev, "返回副本，避免外部改掉 prev");
});

test("parseStatus: 空字符串保留上次值", () => {
    const prev = parseStatus(STATUS_CN(), null);
    assert.deepEqual(parseStatus("", prev), prev);
});

test("parseStatus: prev 为 null 时返回空状态而不是抛异常", () => {
    const got = parseStatus("not json", null);
    assert.deepEqual(got, emptyStatus());
});

test("parseStatus: 缺字段时用空值兜底，已有的照常解析", () => {
    const got = parseStatus('{"items":["一个"]}', null);
    assert.deepEqual(got.items, ["一个"]);
    assert.equal(got.im, "");
    assert.equal(got.imLabel, "");
    assert.equal(got.keyboard, false);
    assert.equal(got.preedit, "");
});

test("parseStatus: 过滤候选里的空串和非字符串", () => {
    const got = parseStatus('{"items":["甲","",null,"乙",3]}', null);
    assert.deepEqual(got.items, ["甲", "乙"]);
});

test("parseStatus: 纯键盘布局没有候选", () => {
    const raw = JSON.stringify({
        im: "keyboard-us", imlabel: "en", keyboard: true, items: [],
    });
    const s = parseStatus(raw, null);
    assert.equal(s.keyboard, true);
    assert.deepEqual(s.items, []);
});

// ---------------- parseImList ----------------

test("parseImList: 真实样本两个输入法", () => {
    const list = parseImList(IMLIST(), []);
    assert.equal(list.length, 2);
    assert.equal(list[0].name, "keyboard-us");
    assert.equal(list[0].keyboard, true);
    assert.equal(list[1].name, "rime");
    assert.equal(list[1].keyboard, false);
});

test("parseImList: 空数组保留上一次", () => {
    const prev = parseImList(IMLIST(), []);
    assert.deepEqual(parseImList("[]", prev), prev);
});

test("parseImList: 非法 JSON 保留上一次", () => {
    const prev = parseImList(IMLIST(), []);
    assert.deepEqual(parseImList("{{{", prev), prev);
});

test("parseImList: 丢掉没有 name 的条目", () => {
    const got = parseImList('[{"title":"无名字"},{"name":"rime"}]', []);
    assert.equal(got.length, 1);
    assert.equal(got[0].name, "rime");
});

// ---------------- isAsciiMode ----------------

test("isAsciiMode: 英文字模式标签", () => {
    assert.equal(isAsciiMode("abc"), true);
    assert.equal(isAsciiMode("en"), true);
});

test("isAsciiMode: 中文字模式标签", () => {
    assert.equal(isAsciiMode("万"), false);
    assert.equal(isAsciiMode("中"), false);
    assert.equal(isAsciiMode("ㄓ"), false);
});

test("isAsciiMode: 空标签按中文处理（宁可不切）", () => {
    assert.equal(isAsciiMode(""), false);
    assert.equal(isAsciiMode(null), false);
});

// ---------------- buildImRows ----------------

test("buildImRows: 纯键盘布局只占一行", () => {
    const rows = buildImRows(parseImList(IMLIST(), []), "keyboard-us", "en");
    const kb = rows.filter(r => r.name === "keyboard-us");
    assert.equal(kb.length, 1);
    assert.equal(kb[0].current, true);
});

test("buildImRows: 拼音类拆成中文 + 英文两行", () => {
    const rows = buildImRows(parseImList(IMLIST(), []), "rime", "万");
    const rime = rows.filter(r => r.name === "rime");
    assert.equal(rime.length, 2);
    assert.deepEqual(rime.map(r => r.ascii), [false, true]);
});

test("buildImRows: 只标一个 current —— 地球键靠它算下一项", () => {
    for (const [im, label] of [["rime", "万"], ["rime", "abc"], ["keyboard-us", "en"]]) {
        const rows = buildImRows(parseImList(IMLIST(), []), im, label);
        const cur = rows.filter(r => r.current);
        assert.equal(cur.length, 1, `${im}/${label} 应该恰好一行 current，实际 ${cur.length}`);
        assert.equal(cur[0].name, im);
    }
});

test("buildImRows: 中文态标在中文行，英文态标在英文行", () => {
    const cn = buildImRows(parseImList(IMLIST(), []), "rime", "万")
        .find(r => r.current);
    assert.equal(cn.ascii, false);
    const en = buildImRows(parseImList(IMLIST(), []), "rime", "abc")
        .find(r => r.current);
    assert.equal(en.ascii, true);
});

test("buildImRows: 中文行用子模式标签「万」，不是输入法的「ㄓ」", () => {
    // addon 的 imlist 里 rime.label 是 "ㄓ"（InputMethodEntry::label），
    // 而空格键该显示的子模式标签是 "万"，来自状态文件的 imlabel。
    const rows = buildImRows(parseImList(IMLIST(), []), "rime", "万");
    const cn = rows.find(r => r.name === "rime" && !r.ascii);
    assert.equal(cn.label, "万", "中文行必须用子模式标签");
    assert.notEqual(cn.label, "ㄓ");
});

test("buildImRows: 非当前输入法用自身 label", () => {
    const rows = buildImRows(parseImList(IMLIST(), []), "keyboard-us", "en");
    const rime = rows.find(r => r.name === "rime" && !r.ascii);
    assert.equal(rime.label, "ㄓ", "不是当前输入法时拿不到子模式标签，退回自身 label");
});

test("buildImRows: 英文态时中文行不该用 abc 当标签", () => {
    const rows = buildImRows(parseImList(IMLIST(), []), "rime", "abc");
    const cn = rows.find(r => r.name === "rime" && !r.ascii);
    assert.notEqual(cn.label, "abc", "英文态的子模式标签不能贴到中文行上");
});

test("buildImRows: 空清单返回空数组", () => {
    assert.deepEqual(buildImRows([], "rime", "万"), []);
    assert.deepEqual(buildImRows(null, "rime", "万"), []);
});

// ---------------- nextImRow ----------------

test("nextImRow: 从键盘布局切到拼音中文", () => {
    const rows = buildImRows(parseImList(IMLIST(), []), "keyboard-us", "en");
    const next = nextImRow(rows);
    assert.equal(next.name, "rime");
    assert.equal(next.ascii, false);
});

test("nextImRow: 中文 → 英文子模式", () => {
    const rows = buildImRows(parseImList(IMLIST(), []), "rime", "万");
    const next = nextImRow(rows);
    assert.equal(next.name, "rime");
    assert.equal(next.ascii, true);
});

test("nextImRow: 末尾回到开头（循环）", () => {
    const rows = buildImRows(parseImList(IMLIST(), []), "rime", "abc");
    const next = nextImRow(rows);
    assert.equal(next.name, "keyboard-us", "最后一个应该绕回第一个输入法");
});

test("nextImRow: 没有 current 时从第一项开始", () => {
    const rows = buildImRows(parseImList(IMLIST(), []), "不存在的输入法", "万");
    const next = nextImRow(rows);
    assert.ok(next !== null);
    assert.equal(next.name, "keyboard-us");
});

test("nextImRow: 空清单返回 null", () => {
    assert.equal(nextImRow([]), null);
    assert.equal(nextImRow(null), null);
});

test("nextImRow: 连续点一圈能回到起点", () => {
    const list = parseImList(IMLIST(), []);
    let im = "keyboard-us";
    let label = "en";
    const seen = [];
    for (let i = 0; i < 3; i++) {
        const next = nextImRow(buildImRows(list, im, label));
        seen.push(`${next.name}:${next.ascii}`);
        im = next.name;
        label = next.ascii ? "abc" : "万";
    }
    assert.deepEqual(seen, ["rime:false", "rime:true", "keyboard-us:false"]);
});

// ---------------- 候选切分 ----------------

test("barCandidates: 固定从头取，不跟随翻页", () => {
    const all = ["甲", "乙", "丙", "丁"];
    assert.deepEqual(barCandidates(all, 2), ["甲", "乙"]);
    assert.deepEqual(barCandidates(all, 99), all);
});

test("barCandidates: 非数组返回空", () => {
    assert.deepEqual(barCandidates(null, 3), []);
});

test("expandedCandidates: 跳过顶栏已显示的", () => {
    const all = ["甲", "乙", "丙", "丁"];
    assert.deepEqual(expandedCandidates(all, 2), ["丙", "丁"]);
});

test("expandedCandidates: 不传偏移时全部返回", () => {
    const all = ["甲", "乙"];
    assert.deepEqual(expandedCandidates(all, 0), all);
    assert.deepEqual(expandedCandidates(all, null), all);
});

test("expandedCandidates: 偏移超过总数时返回空而不是负索引", () => {
    assert.deepEqual(expandedCandidates(["甲"], 5), []);
});

test("全量候选：顶栏 + 展开列表正好覆盖全集且不重复", () => {
    const cn = parseStatus(STATUS_CN(), null);
    const all = ["你好", "拟好", "泥蒿", "你", "泥", "尼", "第十个"];
    const bar = barCandidates(all, 3);
    const rest = expandedCandidates(all, bar.length);
    assert.deepEqual([...bar, ...rest], all);
    assert.equal(new Set([...bar, ...rest]).size, all.length);
});

// ---------------- swapEscTilde ----------------

test("swapEscTilde: 把反引号那格换成 Esc", () => {
    const rows = [[{ k: "char", l: "`", s: "~", c: 41, w: 1 }]];
    const out = swapEscTilde(rows);
    assert.equal(out[0][0].l, "Esc");
    assert.equal(out[0][0].c, 1);
});

test("swapEscTilde: 保留原来那格的宽度", () => {
    const rows = [[{ k: "char", l: "`", c: 41, w: 1.5 }]];
    assert.equal(swapEscTilde(rows)[0][0].w, 1.5, "宽度要跟着原位置，否则整行错位");
});

test("swapEscTilde: Fn 层仍然能打出反引号", () => {
    const rows = [[{ k: "char", l: "`", c: 41, w: 1 }]];
    const fn = swapEscTilde(rows)[0][0].fn;
    assert.ok(fn, "必须有 Fn 层，否则换完就再也打不出 `");
    assert.equal(fn.c, 41);
});

test("swapEscTilde: 其他键原样保留", () => {
    const a = { k: "char", l: "1", c: 2, w: 1 };
    const out = swapEscTilde([[a]]);
    assert.strictEqual(out[0][0], a, "不该复制无关的键");
});

test("swapEscTilde: 多行多键只换那一个", () => {
    const rows = [
        [{ k: "char", l: "`", c: 41 }, { k: "char", l: "1", c: 2 }],
        [{ k: "char", l: "q", c: 16 }],
    ];
    const out = swapEscTilde(rows);
    assert.equal(out[0][0].l, "Esc");
    assert.equal(out[0][1].l, "1");
    assert.equal(out[1][0].l, "q");
});

test("swapEscTilde: 空输入不崩", () => {
    assert.deepEqual(swapEscTilde([]), []);
    assert.deepEqual(swapEscTilde(null), []);
    assert.deepEqual(swapEscTilde([[]]), [[]]);
});

// ---------------- actionExists ----------------

test("actionExists: 命中与未命中", () => {
    const list = [{ id: "undo" }, { id: "redo" }];
    assert.equal(actionExists(list, "undo"), true);
    assert.equal(actionExists(list, "missing"), false);
});

test("actionExists: 空表/非法输入", () => {
    assert.equal(actionExists([], "undo"), false);
    assert.equal(actionExists(null, "undo"), false);
});

test("actionExists: 跳过 null 条目", () => {
    assert.equal(actionExists([null, { id: "undo" }], "undo"), true);
    assert.equal(actionExists([null, undefined], "undo"), false);
});

// ---------------- quickBarIndexFor ----------------

test("quickBarIndexFor: 返回正确索引", () => {
    const bar = [{ id: "a" }, { id: "b" }, { id: "c" }];
    assert.equal(quickBarIndexFor(bar, "a"), 0);
    assert.equal(quickBarIndexFor(bar, "c"), 2);
});

test("quickBarIndexFor: 找不到返回 -1（不能返回 0，会误判成第一格）", () => {
    assert.equal(quickBarIndexFor([{ id: "a" }], "missing"), -1);
});

test("quickBarIndexFor: 空表/非法输入返回 -1", () => {
    assert.equal(quickBarIndexFor([], "a"), -1);
    assert.equal(quickBarIndexFor(null, "a"), -1);
});

test("quickBarIndexFor: 重复 id 返回第一个", () => {
    const bar = [{ id: "a" }, { id: "a" }];
    assert.equal(quickBarIndexFor(bar, "a"), 0);
});

// ---------------- hasMore（还有没显示的候选）----------------

test("parseStatus: 读出 hasMore", () => {
    const st = parseStatus(JSON.stringify({
        preedit: "ni", items: ["你"], hasMore: true,
    }), null);
    assert.equal(st.hasMore, true);
});

test("parseStatus: 缺 hasMore 时为 false（不能当成 true）", () => {
    const st = parseStatus(JSON.stringify({ items: ["你"] }), null);
    assert.equal(st.hasMore, false, "缺字段时若当成 true，展开按钮会一直挂着");
});

test("parseStatus: hasMore 和 hasNext 互相独立", () => {
    // rime 的 bulk 列表没有 pageable：hasNext 恒 false，但 hasMore 为 true
    const st = parseStatus(JSON.stringify({
        items: ["你"], hasNext: false, hasMore: true,
    }), null);
    assert.equal(st.hasNext, false);
    assert.equal(st.hasMore, true);
});

test("emptyStatus: hasMore 默认 false", () => {
    assert.equal(emptyStatus().hasMore, false);
});

test("cloneStatus: 保留 hasMore", () => {
    const st = parseStatus(JSON.stringify({ items: ["你"], hasMore: true }), null);
    const copy = cloneStatus(st);
    assert.equal(copy.hasMore, true);
    assert.notStrictEqual(copy, st);
});
