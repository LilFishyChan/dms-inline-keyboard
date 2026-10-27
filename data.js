// fcitx5 addon 输出 → 键盘内部数据模型。
//
// 这一层是纯函数：不碰 QML、不碰进程、不碰文件，输入是 JSON 文本，
// 输出是普通对象。所以可以用 `node --test tests/` 直接验证数据是否正确，
// 不用启动键盘、不用装 addon（真实样本见 tests/fixtures/）。
//
// 数据来源（fcitx5-addon/src/inline-keyboard-status.cpp 写出的两个文件）：
//   inline-keyboard-status.json   面板状态，每 200ms 刷新
//   inline-keyboard-imlist.json   键盘打开时刷新的输入法清单

/// 解析面板状态。
///
/// 解析失败（文件半写、还没生成、字段缺失）时**保留上一次的值**：
/// 直接清空会让候选栏和空格键标识闪一下，体验很差。
///
/// @param {string} raw  addon 写出的 JSON 文本
/// @param {object} prev 上一次解析结果（可为 null）
/// @returns {object} 归一化后的状态
function parseStatus(raw, prev) {
    // 失败路径返回副本：直接返回 prev 会让调用方拿到同一个对象，
    // 后续一旦原地改字段，上次的状态就被污染了（单测抓到的真实问题）。
    const keep = prev ? cloneStatus(prev) : emptyStatus();
    let d;
    try {
        d = JSON.parse(raw);
    } catch (e) {
        return keep;
    }
    if (!d || typeof d !== "object") {
        return keep;
    }

    const items = Array.isArray(d.items) ? d.items.filter(
        x => typeof x === "string" && x.length > 0) : [];

    return {
        // 候选词本身
        items: items,
        preedit: typeof d.preedit === "string" ? d.preedit : "",
        visible: !!d.visible,
        // 纯键盘布局（keyboard-us 这类）没有候选能力
        keyboard: !!d.keyboard,
        im: typeof d.im === "string" ? d.im : "",
        imLabel: typeof d.imlabel === "string" ? d.imlabel : "",
        imIcon: typeof d.imicon === "string" ? d.imicon : "",
        hasPrev: !!d.hasPrev,
        hasNext: !!d.hasNext,
        // 还有没显示的候选（rime 的 bulk 列表没有 pageable，hasNext 恒 false，
        // addon 另外算了个 hasMore）。候选栏靠它决定要不要显示展开按钮。
        hasMore: !!d.hasMore,
    };
}

function cloneStatus(s) {
    return {
        items: Array.isArray(s.items) ? s.items.slice() : [],
        preedit: s.preedit || "",
        visible: !!s.visible,
        keyboard: !!s.keyboard,
        im: s.im || "",
        imLabel: s.imLabel || "",
        imIcon: s.imIcon || "",
        hasPrev: !!s.hasPrev,
        hasNext: !!s.hasNext,
        hasMore: !!s.hasMore,
    };
}

function emptyStatus() {
    return {
        items: [], preedit: "", visible: false, keyboard: false,
        hasMore: false,
        im: "", imLabel: "", imIcon: "", hasPrev: false, hasNext: false,
    };
}

/// 解析输入法清单。
///
/// 空数组 / 非法内容都保留上一次：清单只在键盘打开时刷新，
/// 中间态不该把长按菜单打空。
function cloneIm(x) {
    return {
        name: x.name, title: x.title, label: x.label,
        icon: x.icon, keyboard: !!x.keyboard,
    };
}

function parseImList(raw, prev) {
    // 注意：QML 的 JS 引擎不支持对象展开（{...x}），必须显式复制字段
    const keep = Array.isArray(prev) ? prev.map(cloneIm) : [];
    let d;
    try {
        d = JSON.parse(raw);
    } catch (e) {
        return keep;
    }
    if (!Array.isArray(d) || d.length === 0) {
        return keep;
    }
    const out = [];
    for (const it of d) {
        if (!it || typeof it.name !== "string" || it.name === "") {
            continue;
        }
        out.push({
            name: it.name,
            title: typeof it.title === "string" ? it.title : it.name,
            label: typeof it.label === "string" ? it.label : "",
            icon: typeof it.icon === "string" ? it.icon : "",
            keyboard: !!it.keyboard,
        });
    }
    return out.length > 0 ? out : keep;
}

/// 输入法是否处于「英文字模式」。
///
/// fcitx5 的 inputMethodLabel() 给的是子模式标签：rime 中文是「万」、
/// 英文是「abc」，键盘布局是「en」。判断依据是标签是否为纯 ASCII 字母
/// （"abc"/"en" → 英文；"万"/"中"/"ㄓ" → 中文），比硬编码具体字串通用。
function isAsciiMode(imLabel) {
    if (typeof imLabel !== "string" || imLabel === "") {
        return false;
    }
    return /^[A-Za-z]+$/.test(imLabel);
}

/// 输入法清单 + 当前状态 → 地球键循环用的平铺行。
///
/// 拼音类输入法会拆成「中文」「英文」两行，点哪行就切到哪个状态；
/// 纯键盘布局只有一行。current 只标一行——地球键靠它算下一项，
/// 标错就会出现「点了没反应」。
function buildImRows(imList, currentIm, imLabel) {
    const out = [];
    const list = Array.isArray(imList) ? imList : [];
    const asciiNow = isAsciiMode(imLabel);
    for (const im of list) {
        if (im.keyboard) {
            out.push({
                name: im.name, ascii: false, keyboard: true,
                label: im.label, icon: im.icon,
                text: im.title,
                current: im.name === currentIm,
            });
            continue;
        }
        // 中文行：标签用子模式标签（rime 是「万」）。清单里的 im.label 是
        // 输入法自己的标识（rime 是「ㄓ」），拿它当空格键文字不对。
        // 子模式标签只有「当前输入法」拿得到，其他输入法照旧用 im.label。
        const cnLabel = (im.name === currentIm && !asciiNow && imLabel)
            ? imLabel : im.label;
        out.push({
            name: im.name, ascii: false, keyboard: false,
            label: cnLabel, icon: im.icon,
            text: im.title,
            current: im.name === currentIm && !asciiNow,
        });
        out.push({
            name: im.name, ascii: true, keyboard: false,
            label: "abc", icon: im.icon,
            text: im.title + " - abc",
            current: im.name === currentIm && asciiNow,
        });
    }
    return out;
}

/// 地球键单击：算出下一个要切到哪一项。
///
/// @returns {object|null} 下一项；清单为空时返回 null
function nextImRow(rows) {
    const list = Array.isArray(rows) ? rows : [];
    if (list.length === 0) {
        return null;
    }
    let idx = -1;
    for (let i = 0; i < list.length; i++) {
        if (list[i].current) {
            idx = i;
            break;
        }
    }
    const nextIdx = idx < 0 ? 0 : (idx + 1) % list.length;
    return list[nextIdx];
}

/// 展开列表要显示的候选：跳过顶栏已经显示的那几个。
///
/// @param {string[]} all  全量候选
/// @param {number} shownInBar 顶栏已显示的个数
function expandedCandidates(all, shownInBar) {
    const list = Array.isArray(all) ? all : [];
    const n = Number.isInteger(shownInBar) && shownInBar > 0 ? shownInBar : 0;
    return n > 0 ? list.slice(n) : list.slice();
}

/// 顶栏显示几个候选：固定从头开始，最多 max 个。
/// 用户要求「固定第一页，不跟随翻页」，所以不做分页偏移。
function barCandidates(all, max) {
    const list = Array.isArray(all) ? all : [];
    const n = Number.isInteger(max) && max > 0 ? max : list.length;
    return list.slice(0, n);
}

/// Esc 与 `` ` ``/`~` 对调：把布局里 keycode 41（反引号）那格换成 Esc。
///
/// 想按习惯把 Esc 放左上角的人用（设置项 escSwap）。只换显示和键码，
/// 宽度、Fn 层都跟着原位置走。
function swapEscTilde(layoutRows) {
    const rows = Array.isArray(layoutRows) ? layoutRows : []
    const out = []
    for (const source of rows) {
        const row = []
        for (const key of (source || [])) {
            if (key && key.k === "char" && key.c === 41) {
                // Fn 层保留原来的反引号，否则切到 Fn 就再也打不出 ` 了
                row.push({ k: "char", l: "Esc", c: 1, w: key.w,
                           fn: { l: "`", c: 41 } })
            } else {
                row.push(key)
            }
        }
        out.push(row)
    }
    return out
}

/// 动作表里有没有这个 id。用于拖动落盘前判断目标还在不在。
function actionExists(actions, id) {
    const list = Array.isArray(actions) ? actions : []
    for (const a of list) {
        if (a && a.id === id) {
            return true
        }
    }
    return false
}

/// 某个动作在快捷栏里的索引，找不到返回 -1。
/// 拖动落点与「哪一格让位」都靠它换算。
function quickBarIndexFor(quickBarResolved, id) {
    const list = Array.isArray(quickBarResolved) ? quickBarResolved : []
    for (let i = 0; i < list.length; i++) {
        if (list[i] && list[i].id === id) {
            return i
        }
    }
    return -1
}

// QML 里没有 CommonJS 的 module，直接加载这个文件会报 ReferenceError。
// 加个守卫：浏览器/QML 环境跳过导出，Node 测试环境正常导出。
const __exports = {
    emptyStatus,
    cloneStatus,
    parseStatus,
    parseImList,
    isAsciiMode,
    buildImRows,
    nextImRow,
    expandedCandidates,
    barCandidates,
    swapEscTilde,
    actionExists,
    quickBarIndexFor,
};

if (typeof module !== "undefined" && module.exports) {
    module.exports = __exports
}
