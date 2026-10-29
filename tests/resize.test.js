// layouts/resize.js 的单元测试：node --test tests/
//
// 这块逻辑的错法全都很隐蔽：框画的位置和松手后的尺寸不一致、拖角落把键盘
// 拉变形、拖到边界后另一轴没跟着收。这些在手势下极难复现，所以每条规则
// 都在这里钉住。
const assert = require("node:assert");
const { test } = require("node:test");
const fs = require("node:fs");
const path = require("node:path");

function loadResize() {
    const file = path.join(__dirname, "..", "layouts", "resize.js");
    const src = fs.readFileSync(file, "utf8").replace(/^\.pragma library\s*$/m, "");
    const mod = { exports: {} };
    new Function("module", "exports", src)(mod, mod.exports);
    return mod.exports;
}

const R = loadResize();

const BOUNDS = { minW: 800, minH: 350, maxW: 1920, maxH: 1080 };

function plan(handle, dx, dy, extra) {
    return R.planResize(Object.assign({
        handle: handle,
        start: { w: 1000, h: 400 },
        dx: dx,
        dy: dy,
        minW: BOUNDS.minW,
        minH: BOUNDS.minH,
        maxW: BOUNDS.maxW,
        maxH: BOUNDS.maxH
    }, extra || {}));
}

test("resize: 拖上边往上是长高", () => {
    const got = plan("n", 0, -50);
    assert.equal(got.h, 450);
    assert.equal(got.w, 1000, "宽度不该变");
});

test("resize: 拖上边往下是变矮", () => {
    assert.equal(plan("n", 0, 30).h, 370);
});

test("resize: 拖下边往下是长高", () => {
    assert.equal(plan("s", 0, 50).h, 450);
});

test("resize: 拖右边往右是变宽", () => {
    const got = plan("e", 80, 0);
    assert.equal(got.w, 1080);
    assert.equal(got.h, 400, "高度不该变");
});

test("resize: 拖左边往左是变宽", () => {
    assert.equal(plan("w", -80, 0).w, 1080);
});

test("resize: 拖左边往右是变窄", () => {
    assert.equal(plan("w", 40, 0).w, 960);
});

test("resize: 对称模式宽度变化是位移的两倍", () => {
    // 停靠时拖左边，右边跟着反向动，视觉上宽度变化 = 2 × 位移
    const got = plan("w", -50, 0, { symmetric: true });
    assert.equal(got.w, 1100);
});

test("resize: 对称模式对上下没有影响", () => {
    const got = plan("e", 50, 20, { symmetric: true });
    assert.equal(got.w, 1100);
    assert.equal(got.h, 400, "symmetric 只作用于宽度");
});

test("resize: 四角等比缩放保持宽高比", () => {
    const aspect = 1000 / 400;   // 2.5
    const got = plan("se", 100, 0, { aspect: aspect });
    assert.equal(got.w, 1100);
    assert.equal(got.h, 440, "高度按比例跟涨");
});

test("resize: 四角等比时宽度被上限截断，高度按比例回收", () => {
    const aspect = 1000 / 400;
    // 起始 1000×400，往右拖 2000 → 宽度撞到 maxW=1920
    const got = plan("se", 2000, 0, { aspect: aspect });
    assert.equal(got.w, 1920);
    assert.equal(got.h, Math.round(1920 / aspect), "高度跟着 1920 的比例算");
});

test("resize: 四角等比时高度撞下限，宽度跟着收", () => {
    const aspect = 1000 / 400;
    // 往左上拖很多 → 高度会撞 minH=350
    const got = plan("nw", 500, 500, { aspect: aspect });
    assert.equal(got.h, 350);
    assert.equal(got.w, Math.round(350 * aspect));
});

test("resize: 上下限生效", () => {
    assert.equal(plan("e", 99999, 0).w, 1920, "不能超过 maxW");
    assert.equal(plan("e", -99999, 0).w, 800, "不能低于 minW");
    assert.equal(plan("n", 0, 99999).h, 350, "变矮到 minH 为止");
});

test("resize: 非法手柄原样返回起始尺寸", () => {
    const got = plan("garbage", 100, 100);
    assert.deepEqual(got, { w: 1000, h: 400 });
});

test("resize: 结果是整数", () => {
    const got = plan("e", 33.7, 0);
    assert.equal(got.w % 1, 0);
});

test("resize: 停靠模式可用手柄不含底边和底部两角", () => {
    assert.equal(R.DOCKED_HANDLES.indexOf("s"), -1, "底边不给拖");
    assert.equal(R.DOCKED_HANDLES.indexOf("se"), -1);
    assert.equal(R.DOCKED_HANDLES.indexOf("sw"), -1);
    assert.ok(R.DOCKED_HANDLES.indexOf("n") >= 0, "顶边仍可调高度");
    assert.ok(R.DOCKED_HANDLES.indexOf("e") >= 0);
    assert.ok(R.DOCKED_HANDLES.indexOf("w") >= 0);
});

test("resize: isCorner 认四个角", () => {
    assert.equal(R.isCorner("ne"), true);
    assert.equal(R.isCorner("sw"), true);
    assert.equal(R.isCorner("n"), false);
    assert.equal(R.isCorner("e"), false);
});

test("resize: resetSize 回到名义尺寸", () => {
    assert.deepEqual(R.resetSize(1050, 444, 840, 355), { w: 1050, h: 444 });
});

test("resize: normalizeSize 把存储值夹进范围", () => {
    // 缩放 1.0，屏幕 1920×1080 → 上限就是屏幕
    const got = R.normalizeSize({ w: 99999, h: 99999 }, 1050, 444, 1920, 1080, 1);
    assert.equal(got.w, 1920);
    assert.equal(got.h, 1080);
});

test("resize: normalizeSize 会按缩放缩小上限", () => {
    // 缩放 0.5 时，拖拽结果 3840 才会填满 1920 的屏幕
    const got = R.normalizeSize({ w: 99999, h: 99999 }, 1050, 444, 1920, 1080, 0.5);
    assert.equal(got.w, 3840);
    assert.equal(got.h, 2160);
});

test("resize: normalizeSize 对缺省/非法值回落到名义尺寸", () => {
    for (const bad of [null, undefined, {}, { w: 0, h: 0 }, { w: NaN, h: "x" }]) {
        const got = R.normalizeSize(bad, 1050, 444, 1920, 1080, 1);
        assert.equal(got.w, 1050, "输入 " + JSON.stringify(bad));
        assert.equal(got.h, 444);
    }
});

test("resize: normalizeSize 的下限也有 80% 保护", () => {
    const got = R.normalizeSize({ w: 1, h: 1 }, 1050, 444, 1920, 1080, 1);
    assert.equal(got.w, 840, "1050 * 0.8");
    assert.equal(got.h, Math.round(444 * 0.8));
});

test("planResize: 纵向只动被拖的那条边（没有对称模式）", () => {
    // 拖上边向上 50px：只把上边往上推，高度 +50
    assert.equal(plan("n", 0, -50).h, 450);
    // 拖下边向下 50px：同样只 +50
    assert.equal(plan("s", 0, 50).h, 450);
});

test("planResize: symmetric 只管横轴", () => {
    const onlyX = plan("e", 100, 0, { symmetric: true });
    assert.equal(onlyX.w, 1200);
    assert.equal(onlyX.h, 400, "横轴对称不该影响高度");
});
