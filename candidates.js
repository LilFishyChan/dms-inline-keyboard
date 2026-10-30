// 候选列表页的分行与宽度分配：纯函数，node --test 可测。
// 测宽由调用方注入（QML 里是 TextMetrics，测试里是假函数）。

function num(v) {
    return typeof v === "number" && isFinite(v) ? v : 0
}

// 分行按「文字宽 + 左右内边距」算，分行之后再分配余量：
// 等分会把宽词压窄（= 截断文字），按份加宽才能既保住每个词、行尾又铺满。
function layoutCandidates(list, measure, opts) {
    const src = list || []
    const o = opts || {}
    const availW = Math.max(0, num(o.availW))
    const gap = num(o.gap)
    const rowH = num(o.rowH)
    const pad = num(o.pad)
    const step = rowH + gap

    const items = []
    const rows = []
    let y = 0
    let x = 0
    let row = []

    for (let n = 0; n < src.length; n++) {
        const item = src[n] || {}
        const text = item.t !== undefined ? String(item.t) : String(item)
        const adv = measure ? num(measure(text)) : 0
        const w = Math.min(Math.ceil(adv + pad), availW)

        if (x > 0 && x + w > availW) {
            // 换行：上一行最后一项不画分隔线
            if (row.length > 0)
                row[row.length - 1].sep = false
            rows.push(row)
            row = []
            y += step
            x = 0
        }

        const cell = {
            x: x,
            w: w,
            t: text,
            sep: true,
            i: item.i !== undefined ? item.i : n
        }
        row.push(cell)
        items.push(cell)
        x += w + gap
    }
    if (row.length > 0) {
        row[row.length - 1].sep = false
        rows.push(row)
    }

    for (let r = 0; r < rows.length; r++) {
        const cells = rows[r]
        const n = cells.length
        if (n === 0)
            continue
        let used = (n - 1) * gap
        for (let i = 0; i < n; i++)
            used += cells[i].w
        const share = Math.floor(Math.max(0, availW - used) / n)
        let cursor = 0
        for (let i = 0; i < n; i++) {
            cells[i].x = cursor
            cells[i].w += share
            cursor += cells[i].w + gap
        }
        // 除不尽的零头补给最后一项，右边界才贴着 availW
        const last = cells[n - 1]
        last.w = Math.max(last.w, availW - last.x)
    }

    return {
        items: items,
        rows: rows,
        // y 是最后一行的起点，内容高到它的下沿（不含行间距）
        contentH: Math.max(0, rows.length > 0 ? y + rowH : 0)
    }
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = { layoutCandidates: layoutCandidates }
}
