// actions.js 的单元测试：node --test tests/
const assert = require("node:assert");
const { test } = require("node:test");
const {
    sanitizeActions,
    moveActionById,
    visibleActions,
    dropIndexAt,
    quickBarInsertIndex,
    planQuickBarDrop,
    toArray,
    quickBarViewActions,
    markBuiltin, removeAction, updateAction, appendAction, moveActionToEndById,
    mergeNewBuiltins, defaultActions
} = require("../actions.js");

// 测试用的动作工厂：字段要和 sanitizeActions 的输出完全一致，
// 多一个少一个 deepEqual 都会失败（加了 kind 后就要同步补上）
const A = (id, label = id, icon = "") =>
    ({ id, label, icon, hidden: false, builtin: false, kind: "builtin", cmd: "" });

test("sanitizeActions: 非数组返回 fallback 副本", () => {
    const fallback = [A("undo")];
    const result = sanitizeActions(null, fallback);
    assert.deepEqual(result, fallback);
    assert.notStrictEqual(result, fallback, "必须是副本，不能共享引用");
});

test("sanitizeActions: 丢弃 null / 无 id / 非对象项", () => {
    const result = sanitizeActions(
        [null, undefined, 42, "str", {}, { id: "" }, { id: "  " }, A("undo")],
        []
    );
    assert.deepEqual(result, [A("undo")]);
});

test("sanitizeActions: 按 id 去重，保留第一次出现的", () => {
    const result = sanitizeActions([A("undo", "撤销"), A("undo", "第二次")], []);
    assert.equal(result.length, 1);
    assert.equal(result[0].label, "撤销");
});

test("sanitizeActions: 全部无效时回落到 fallback", () => {
    const fallback = [A("undo")];
    assert.deepEqual(sanitizeActions([null, {}], fallback), fallback);
});

test("moveActionById: 同 id 不动", () => {
    const list = [A("a"), A("b")];
    assert.deepEqual(moveActionById(list, "a", "a"), list);
});

test("moveActionById: 向后移动", () => {
    const list = [A("a"), A("b"), A("c")];
    assert.deepEqual(
        moveActionById(list, "a", "c").map(x => x.id),
        ["b", "c", "a"]
    );
});

test("moveActionById: 向前移动", () => {
    const list = [A("a"), A("b"), A("c")];
    assert.deepEqual(
        moveActionById(list, "c", "a").map(x => x.id),
        ["c", "a", "b"]
    );
});

test("moveActionById: id 不存在时返回副本且不改原数组", () => {
    const list = [A("a"), A("b")];
    const result = moveActionById(list, "a", "zzz");
    assert.deepEqual(result.map(x => x.id), ["a", "b"]);
    assert.notStrictEqual(result, list);
});

test("moveActionById: 空数组不抛异常", () => {
    assert.deepEqual(moveActionById([], "a", "b"), []);
    assert.deepEqual(moveActionById(null, "a", "b"), []);
});

test("visibleActions: 过滤掉槽内和快捷栏内的动作", () => {
    const all = [A("undo"), A("float"), A("mic"), A("settings")];
    const quick = [A("float")];
    assert.deepEqual(
        visibleActions(all, "mic", quick).map(x => x.id),
        ["undo", "settings"]
    );
});

test("visibleActions: 槽为空时不隐藏任何动作", () => {
    const all = [A("undo"), A("mic")];
    assert.deepEqual(visibleActions(all, "", []).map(x => x.id), ["undo", "mic"]);
});

test("visibleActions: 保持原顺序", () => {
    const all = [A("c"), A("a"), A("b")];
    assert.deepEqual(visibleActions(all, "", []).map(x => x.id), ["c", "a", "b"]);
});

test("dropIndexAt: 左上角落在第 0 格", () => {
    assert.equal(dropIndexAt(0, 0, 400, 8, 60, 6, 4), 0);
});

test("dropIndexAt: 第 2 行第 1 列", () => {
    // cellWidth = (400 - 3*6)/4 = 95.5；x=100 → col=0（100/101.5）；y=66 → row=1
    assert.equal(dropIndexAt(100, 66, 400, 8, 60, 6, 4), 4);
});

test("dropIndexAt: 超出右下角时夹到最后一格", () => {
    assert.equal(dropIndexAt(9999, 9999, 400, 5, 60, 6, 4), 5, "末尾（可追加）");
});

test("dropIndexAt: 数量为 0 时返回 -1", () => {
    assert.equal(dropIndexAt(10, 10, 400, 0, 60, 6, 4), -1);
});

// ---------------- 固定栏插入位置 ----------------
test("quickBarInsertIndex: 空栏 → 0", () => {
    assert.equal(quickBarInsertIndex(100, 0, 80, 10), 0);
});

test("quickBarInsertIndex: 落在第一个动作左半边 → 0", () => {
    // slotW=80, slotGap=10：第 0 个中心 = 10 + 40 = 50
    assert.equal(quickBarInsertIndex(20, 3, 80, 10), 0);
});

test("quickBarInsertIndex: 落在两个动作之间 → 中间索引", () => {
    // 中心：50 / 140 / 230
    assert.equal(quickBarInsertIndex(95, 3, 80, 10), 1);
    assert.equal(quickBarInsertIndex(185, 3, 80, 10), 2);
});

test("quickBarInsertIndex: 越过最后一个 → count", () => {
    assert.equal(quickBarInsertIndex(500, 3, 80, 10), 3);
});

// ---------------- 落到固定栏的结果 ----------------
const L = (...ids) => ids.map(id => ({ id, label: id, icon: "" }));

test("planQuickBarDrop: 从列表拖进空栏", () => {
    const plan = planQuickBarDrop({
        bar: [], actionList: L("a", "b"), action: L("a")[0], index: 0, capacity: 4
    });
    assert.deepEqual(plan.bar.map(x => x.id), ["a"]);
    assert.equal(plan.insertedAt, 0);
    assert.equal(plan.ejected, null);
});

test("planQuickBarDrop: 插到中间（列表 → 固定栏）", () => {
    const plan = planQuickBarDrop({
        bar: L("a", "c"), actionList: L("a", "b", "c"), action: L("b")[0], index: 1, capacity: 4
    });
    assert.deepEqual(plan.bar.map(x => x.id), ["a", "b", "c"]);
    assert.equal(plan.insertedAt, 1);
});

test("planQuickBarDrop: 固定栏内部往后移动", () => {
    // 把 a（索引 0）拖到 c 右边（插入位置 3 → 移除自己后变 2）
    const plan = planQuickBarDrop({
        bar: L("a", "b", "c"), actionList: L("a", "b", "c"),
        action: L("a")[0], index: 3, capacity: 4, source: "bar", sourceIndex: 0
    });
    assert.deepEqual(plan.bar.map(x => x.id), ["b", "c", "a"]);
    assert.equal(plan.insertedAt, 2);
});

test("planQuickBarDrop: 固定栏内部往前移动", () => {
    const plan = planQuickBarDrop({
        bar: L("a", "b", "c"), actionList: L("a", "b", "c"),
        action: L("c")[0], index: 0, capacity: 4, source: "bar", sourceIndex: 2
    });
    assert.deepEqual(plan.bar.map(x => x.id), ["c", "a", "b"]);
    assert.equal(plan.insertedAt, 0);
});

test("planQuickBarDrop: 从槽拖进固定栏，槽清空", () => {
    const plan = planQuickBarDrop({
        bar: L("a"), actionList: L("a", "m"), action: L("m")[0], index: 1,
        capacity: 4, slotActionId: "m", source: "slot"
    });
    assert.deepEqual(plan.bar.map(x => x.id), ["a", "m"]);
    assert.equal(plan.slotActionId, "", "槽里的动作挪到固定栏后槽要空");
});

test("planQuickBarDrop: 满了挤出末尾，放到动作表第一个", () => {
    const plan = planQuickBarDrop({
        bar: L("a", "b"), actionList: L("a", "b", "c", "x"), action: L("c")[0],
        index: 1, capacity: 2
    });
    assert.deepEqual(plan.bar.map(x => x.id), ["a", "c"], "b 被挤出");
    assert.equal(plan.ejected.id, "b");
    assert.deepEqual(plan.actionList.map(x => x.id), ["b", "a", "c", "x"],
        "被挤出的排到动作表最前，且不重复");
});

test("planQuickBarDrop: 容量 1 时新动作替换旧动作", () => {
    const plan = planQuickBarDrop({
        bar: L("a"), actionList: L("a", "b"), action: L("b")[0], index: 1, capacity: 1
    });
    assert.deepEqual(plan.bar.map(x => x.id), ["b"]);
    assert.equal(plan.ejected.id, "a");
    assert.equal(plan.actionList[0].id, "a");
});

test("planQuickBarDrop: 挤出的动作原本就在动作表里，不能重复", () => {
    const plan = planQuickBarDrop({
        bar: L("a", "b"), actionList: L("b", "a", "c"), action: L("c")[0],
        index: 2, capacity: 2
    });
    assert.deepEqual(plan.actionList.map(x => x.id).sort(), ["a", "b", "c"]);
    assert.equal(plan.actionList.filter(x => x.id === "a").length, 1);
});

test("planQuickBarDrop: 没有动作时原样返回", () => {
    const plan = planQuickBarDrop({ bar: L("a"), actionList: L("a"), action: null, index: 0, capacity: 4 });
    assert.deepEqual(plan.bar.map(x => x.id), ["a"]);
    assert.equal(plan.insertedAt, -1);
});

test("planQuickBarDrop: 动作已经在固定栏里，不会插出重复项", () => {
    // 界面数据不同步时会把已在固定栏的动作再拖一次
    const plan = planQuickBarDrop({
        bar: L("a", "b", "c"), actionList: L("a", "b", "c"), action: L("a")[0],
        index: 2, capacity: 6
    });
    assert.deepEqual(plan.bar.map(x => x.id), ["b", "a", "c"], "a 只出现一次，插到 c 前面");
    assert.equal(plan.bar.filter(x => x.id === "a").length, 1);
});

test("planQuickBarDrop: 重复动作 + 满栏，也不会挤出多余的项", () => {
    const plan = planQuickBarDrop({
        bar: L("a", "b", "c"), actionList: L("a", "b", "c", "d"), action: L("a")[0],
        index: 3, capacity: 3
    });
    assert.deepEqual(plan.bar.map(x => x.id), ["b", "c", "a"]);
    assert.equal(plan.ejected, null, "没有真的超出容量，不该挤出任何东西");
});


// ---------- QML 会把数组包成类数组对象，Array.isArray 为 false ----------
// 这里用 {length, 0:.., 1:..} 模拟那种对象；不处理的话整个列表会变空
const pseudo = (...items) => {
    const o = { length: items.length };
    items.forEach((v, i) => { o[i] = v; });
    return o;
};

test("toArray: 类数组对象转成真数组", () => {
    const arr = toArray(pseudo({ id: "a" }, { id: "b" }));
    assert.ok(Array.isArray(arr));
    assert.deepEqual(arr.map(x => x.id), ["a", "b"]);
});

test("toArray: null / 无 length 的值返回空数组", () => {
    assert.deepEqual(toArray(null), []);
    assert.deepEqual(toArray({}), []);
    assert.deepEqual(toArray("abc"), []);
});

test("visibleActions: 传入类数组时仍然正确过滤", () => {
    const result = visibleActions(pseudo(A("a"), A("b"), A("c")), "c", pseudo(A("a")));
    assert.deepEqual(result.map(x => x.id), ["b"]);
});

test("sanitizeActions: 传入类数组时不会退化成默认动作", () => {
    const clean = sanitizeActions(pseudo(A("a"), A("a"), A("b")), [A("fallback")]);
    assert.deepEqual(clean.map(x => x.id), ["a", "b"], "按 id 去重后保留两个");
});

test("moveActionById: 传入类数组时也能重排", () => {
    const moved = moveActionById(pseudo(A("a"), A("b"), A("c")), "c", "a");
    assert.deepEqual(moved.map(x => x.id), ["c", "a", "b"]);
});

test("planQuickBarDrop: 动作表和固定栏是类数组时也能工作", () => {
    const plan = planQuickBarDrop({
        bar: pseudo(A("a")),
        actionList: pseudo(A("a"), A("b")),
        action: A("b"),
        index: 1,
        capacity: 4
    });
    assert.deepEqual(plan.bar.map(x => x.id), ["a", "b"]);
});


// ---------- 固定栏在拖动中的渲染数组 ----------
test("quickBarViewActions: 没在拖动时就是真实数组", () => {
    const view = quickBarViewActions({ bar: L("a", "b"), plan: null, frozen: null, dragActive: false });
    assert.deepEqual(view.map(x => x.id), ["a", "b"]);
});

test("quickBarViewActions: 落在固定栏内时用 plan 的结果", () => {
    const view = quickBarViewActions({
        bar: L("a", "b"),
        plan: { bar: L("a", "x", "b") },
        frozen: L("a", "b"),
        dragActive: true,
        dragFrom: "cell",
        dragFromIndex: -1
    });
    assert.deepEqual(view.map(x => x.id), ["a", "x", "b"], "plan 优先于 frozen");
});

test("quickBarViewActions: 松手后优先用冻结数组", () => {
    const view = quickBarViewActions({
        bar: L("a"), plan: null, frozen: L("b", "a"), dragActive: false
    });
    assert.deepEqual(view.map(x => x.id), ["b", "a"]);
});

test("quickBarViewActions: 从固定栏拖出去时，源动作从预览里消失", () => {
    const view = quickBarViewActions({
        bar: L("a", "b", "c"),
        plan: null,
        frozen: null,
        dragActive: true,
        dragFrom: "bar",
        dragFromIndex: 1
    });
    assert.deepEqual(view.map(x => x.id), ["a", "c"], "b 被拖走，c 补齐");
});

test("quickBarViewActions: 拖的是第一个 / 最后一个也对", () => {
    const first = quickBarViewActions({
        bar: L("a", "b"), plan: null, frozen: null,
        dragActive: true, dragFrom: "bar", dragFromIndex: 0
    });
    assert.deepEqual(first.map(x => x.id), ["b"]);
    const last = quickBarViewActions({
        bar: L("a", "b"), plan: null, frozen: null,
        dragActive: true, dragFrom: "bar", dragFromIndex: 1
    });
    assert.deepEqual(last.map(x => x.id), ["a"]);
});

test("quickBarViewActions: 源索引越界 / 源不是固定栏时不动数组", () => {
    const bad = quickBarViewActions({
        bar: L("a", "b"), plan: null, frozen: null,
        dragActive: true, dragFrom: "bar", dragFromIndex: 9
    });
    assert.deepEqual(bad.map(x => x.id), ["a", "b"]);
    const fromList = quickBarViewActions({
        bar: L("a", "b"), plan: null, frozen: null,
        dragActive: true, dragFrom: "", dragFromIndex: 0
    });
    assert.deepEqual(fromList.map(x => x.id), ["a", "b"]);
});

test("quickBarViewActions: 类数组也能处理", () => {
    const view = quickBarViewActions({
        bar: pseudo(A("a"), A("b")), plan: null, frozen: null,
        dragActive: true, dragFrom: "bar", dragFromIndex: 0
    });
    assert.deepEqual(view.map(x => x.id), ["b"]);
});


// ---------- 动作的隐藏 / 删除 / 编辑 ----------
test("markBuiltin: 默认动作都打上 builtin:true", () => {
    const list = markBuiltin([{ id: "a", label: "A", icon: "star" }, { id: "b" }]);
    assert.equal(list.length, 2);
    assert.ok(list.every(a => a.builtin === true));
    assert.equal(list[0].label, "A");
});

test("sanitizeActions: 保留 hidden / builtin 字段", () => {
    const clean = sanitizeActions(
        [{ id: "a", label: "A", icon: "x", hidden: true, builtin: true }], []);
    assert.equal(clean[0].hidden, true);
    assert.equal(clean[0].builtin, true);
    const plain = sanitizeActions([{ id: "b" }], []);
    assert.equal(plain[0].hidden, false, "缺省不算隐藏");
});

test("visibleActions: hidden 的动作不进列表", () => {
    const all = [{ id: "a" }, { id: "b", hidden: true }, { id: "c" }];
    assert.deepEqual(visibleActions(all, "", []).map(x => x.id), ["a", "c"]);
});

test("visibleActions: 隐藏但仍在固定栏里的动作照常被过滤，不重复显示", () => {
    const all = [{ id: "a", hidden: true }, { id: "b" }];
    assert.deepEqual(visibleActions(all, "", [{ id: "a" }]).map(x => x.id), ["b"]);
});

test("removeAction: 自定义动作可以删", () => {
    const r = removeAction([{ id: "a" }, { id: "u1", builtin: false }], "u1");
    assert.deepEqual(r.actions.map(x => x.id), ["a"]);
    assert.equal(r.removed, true);
});

test("removeAction: 内置动作删不掉", () => {
    const r = removeAction([{ id: "a", builtin: true }, { id: "b" }], "a");
    assert.deepEqual(r.actions.map(x => x.id), ["a", "b"]);
    assert.equal(r.removed, false);
});

test("updateAction: 改图标 / 名称 / 隐藏", () => {
    const list = [{ id: "a", label: "A", icon: "star", hidden: false, builtin: true }];
    assert.equal(updateAction(list, "a", { icon: "bolt" })[0].icon, "bolt");
    assert.equal(updateAction(list, "a", { label: "B" })[0].label, "B");
    assert.equal(updateAction(list, "a", { hidden: true })[0].hidden, true);
    assert.equal(updateAction(list, "a", { icon: "bolt" })[0].builtin, true, "其他字段保留");
});

test("updateAction: id 不存在时原样返回", () => {
    const list = [{ id: "a" }];
    assert.deepEqual(updateAction(list, "zzz", { icon: "x" }), list);
});

test("appendAction: 追加自定义动作，id 不撞", () => {
    const first = appendAction([{ id: "a" }], { label: "New", icon: "star" }, 111);
    assert.equal(first.actions.length, 2);
    assert.equal(first.action.builtin, false);
    assert.equal(first.action.id, "u111");
    const second = appendAction(first.actions, { label: "Again" }, 111);
    assert.notEqual(second.action.id, "u111", "同 seed 也要换一个 id");
    assert.equal(second.actions.length, 3);
});

test("sanitizeActions: 老配置里没有 builtin 字段，按默认动作表补上", () => {
    const fallback = [{ id: "undo" }, { id: "redo" }];
    const clean = sanitizeActions([{ id: "undo" }, { id: "u1" }], fallback);
    assert.equal(clean[0].builtin, true, "undo 是内置的");
    assert.equal(clean[1].builtin, false, "u1 是自定义的");
});

test("appendAction 之前补默认表：自定义动作全部丢失内置时不会顶掉整张表", () => {
    // 模拟设置页的防御逻辑
    let list = [{ id: "u1", builtin: false }];
    if (!list.some(a => a.builtin === true)) {
        const defaults = [{ id: "undo", builtin: true }, { id: "redo", builtin: true }];
        list = defaults.concat(list.filter(a => a.builtin !== true));
    }
    const r = appendAction(list, { label: "New", icon: "star" }, 7);
    assert.deepEqual(r.actions.map(x => x.id), ["undo", "redo", "u1", "u7"]);
});

// ---------- 拖到列表末尾 ----------
test("dropIndexAt: 落在最后一项之后 → count（追加到末尾）", () => {
    // 4 列，cellW=100 gap=0 cellH=60，count=2 → 最后一格是 row0/col1（x 100..200，中心 150）
    assert.equal(dropIndexAt(10, 10, 400, 2, 60, 0, 4), 0);
    assert.equal(dropIndexAt(160, 10, 400, 2, 60, 0, 4), 2, "最后一格右半边 → 末尾");
    assert.equal(dropIndexAt(120, 10, 400, 2, 60, 0, 4), 1, "最后一格左半边 → 原地");
    assert.equal(dropIndexAt(10, 200, 400, 2, 60, 0, 4), 2, "拖到下一行 → 末尾");
});

test("moveActionToEndById: 挪到末尾", () => {
    assert.deepEqual(moveActionToEndById(L("a", "b", "c"), "a").map(x => x.id), ["b", "c", "a"]);
});

test("moveActionToEndById: 已在末尾 / id 不存在时原样返回", () => {
    assert.deepEqual(moveActionToEndById(L("a", "b"), "b").map(x => x.id), ["a", "b"]);
    assert.deepEqual(moveActionToEndById(L("a", "b"), "zz").map(x => x.id), ["a", "b"]);
});

test("sanitizeActions: kind 按 cmd 有无推断（老配置没有 kind 字段）", () => {
    const result = sanitizeActions([
        { id: "withCmd", cmd: "notify-send hi" },
        { id: "noCmd" },
        { id: "explicitCmd", kind: "cmd", cmd: "echo x" }
    ], []);
    const byId = {};
    for (const a of result)
        byId[a.id] = a;
    assert.equal(byId.withCmd.kind, "cmd", "有 cmd 的命令动作应为 cmd");
    assert.equal(byId.noCmd.kind, "builtin", "没有 cmd 的应为内置动作");
    assert.equal(byId.explicitCmd.kind, "cmd", "显式 kind 优先");
});

test("defaultActions: 全部内置动作都标了 kind=builtin", () => {
    const { defaultActions } = require("../actions.js");
    const list = defaultActions();
    assert.ok(list.length > 0);
    for (const a of list)
        assert.equal(a.kind, "builtin", a.id + " 应该标成 builtin");
});

test("mergeNewBuiltins: 补上老配置缺失的内置动作，已有项顺序不变", () => {
    const kept = { id: "float", label: "浮动", icon: "x", hidden: false, builtin: true, kind: "builtin", cmd: "" };
    const saved = [kept];
    const merged = mergeNewBuiltins(saved, defaultActions());
    // 原有项仍在第一个，引用顺序不变
    assert.equal(merged[0].id, "float");
    assert.equal(merged[0].label, "浮动", "不能覆盖用户改过的名字");
    // 默认表里每个 id 都在结果中，且只出现一次
    const ids = merged.map(a => a.id);
    assert.equal(new Set(ids).size, ids.length, "不能重复");
    for (const d of defaultActions())
        assert.ok(ids.includes(d.id), "缺了 " + d.id);
});

test("mergeNewBuiltins: 新补的动作默认 hidden，不进功能页", () => {
    const merged = mergeNewBuiltins([{ id: "undo", label: "u", icon: "", hidden: false, builtin: true, kind: "builtin", cmd: "" }], defaultActions());
    const added = merged.filter(a => a.id !== "undo");
    assert.ok(added.length > 0);
    for (const a of added) {
        assert.equal(a.hidden, true, a.id + " 应该默认隐藏");
        assert.equal(a.builtin, true);
        assert.equal(a.kind, "builtin");
    }
});

test("mergeNewBuiltins: minimize 在默认动作表里", () => {
    const ids = defaultActions().map(a => a.id);
    assert.ok(ids.includes("minimize"), "默认动作表应包含 minimize");
});
