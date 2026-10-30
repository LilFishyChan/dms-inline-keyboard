.pragma library

// 调整尺寸的几何计算。预览和落盘必须走同一个函数，否则松手后尺寸会变。
// dx/dy 相对按下点（屏幕坐标，右/下为正）；symmetric 时另一边反向同幅变化

// 手柄标识：n/s/e/w 是四条边，ne/nw/se/sw 是四个角
const HANDLES = ["n", "s", "e", "w", "ne", "nw", "se", "sw"];

// 停靠模式可用的手柄：去掉底边和底部两角（键盘贴着屏幕底，拖不了下面）
const DOCKED_HANDLES = ["n", "e", "w", "ne", "nw"];

function isCorner(handle) {
    return handle === "ne" || handle === "nw" || handle === "se" || handle === "sw";
}

function isValidHandle(handle) {
    return HANDLES.indexOf(handle) >= 0;
}

function clamp(value, low, high) {
    if (high < low)
        return low;
    return Math.max(low, Math.min(high, value));
}

// 算出拖动后的目标尺寸。
// opts = {
function planResize(opts) {
    const handle = opts.handle;
    const start = opts.start || { w: 0, h: 0 };
    const minW = opts.minW !== undefined ? opts.minW : 0;
    const minH = opts.minH !== undefined ? opts.minH : 0;
    const maxW = opts.maxW !== undefined ? opts.maxW : Number.MAX_VALUE;
    const maxH = opts.maxH !== undefined ? opts.maxH : Number.MAX_VALUE;
    const aspect = opts.aspect || 0;

    if (!isValidHandle(handle))
        return { w: clamp(start.w, minW, maxW), h: clamp(start.h, minH, maxH) };

    const touchesW = handle.indexOf("e") >= 0 || handle.indexOf("w") >= 0;
    const touchesH = handle.indexOf("n") >= 0 || handle.indexOf("s") >= 0;

    let w = start.w;
    let h = start.h;

    if (touchesW) {
        // 往右拖（dx > 0）时 e 变宽、w 变窄
        const sign = handle.indexOf("e") >= 0 ? 1 : -1;
        // 对称：另一边跟着反向同幅动，视觉宽度变化是位移的两倍
        const scale = opts.symmetric ? 2 : 1;
        w = start.w + sign * opts.dx * scale;
    }

    if (touchesH) {
        // 往下拖（dy > 0）时 s 变高、n 变矮
        const sign = handle.indexOf("s") >= 0 ? 1 : -1;
        h = start.h + sign * opts.dy;
    }

    // 四角按当前比例缩放：以宽度的变化为准，高度跟着算
    // （宽度是用户更容易控制的轴，且宽度上限更常见）
    if (isCorner(handle) && aspect > 0 && w > 0) {
        h = w / aspect;
    }

    w = clamp(w, minW, maxW);
    h = clamp(h, minH, maxH);

    // 角落等比时，某一轴被上限截断后另一轴要把比例拉回来，
    // 否则松手后键盘会变形（和拖动中看到的预览不一致）
    if (isCorner(handle) && aspect > 0 && w > 0 && h > 0) {
        const wantH = w / aspect;
        if (wantH > maxH) {
            h = maxH;
            w = clamp(h * aspect, minW, maxW);
        } else if (wantH < minH) {
            h = minH;
            w = clamp(h * aspect, minW, maxW);
        } else {
            h = wantH;
        }
    }

    return { w: Math.round(w), h: Math.round(h) };
}

// 重置值：回到名义尺寸（baseKbWidth × baseKbHeight），不乘缩放
function resetSize(baseW, baseH, minW, minH) {
    return {
        w: clamp(baseW, minW, Math.max(minW, baseW)),
        h: clamp(baseH, minH, Math.max(minH, baseH))
    };
}

// 把设置里存的尺寸夹进当前允许的范围（屏幕旋转、缩放改了之后要用）
function normalizeSize(stored, baseW, baseH, maxW, maxH, factor) {
    const k = factor > 0 ? factor : 1;
    const minW = baseW * 0.8;
    const minH = baseH * 0.8;
    // 存的是「拖拽结果」，乘上缩放后不能超出屏幕 → 上限要除以缩放
    const limitW = maxW / k;
    const limitH = maxH / k;
    const w = Number(stored && stored.w);
    const h = Number(stored && stored.h);
    return {
        w: Math.round(clamp(isFinite(w) && w > 0 ? w : baseW, minW, Math.max(minW, limitW))),
        h: Math.round(clamp(isFinite(h) && h > 0 ? h : baseH, minH, Math.max(minH, limitH)))
    };
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        HANDLES: HANDLES,
        DOCKED_HANDLES: DOCKED_HANDLES,
        isCorner: isCorner,
        isValidHandle: isValidHandle,
        clamp: clamp,
        planResize: planResize,
        resetSize: resetSize,
        normalizeSize: normalizeSize
    };
}
