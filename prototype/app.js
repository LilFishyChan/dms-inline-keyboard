const $ = (id) => document.getElementById(id);
// 每行统一 15 个布局单位（真键盘主键区宽度）
const UNITS = 15;
const screenEl = $("screen");
const kbEl = $("keyboard");
const keysEl = $("keys");
const candbarEl = $("candbar");
const candsEl = $("cands");
const preeditEl = $("preedit");
const handlebarEl = $("handlebar");

const DEFAULTS = {
  mode: "docked",
  page: "page1",
  kbW: 1050,
  kbH: 387,
  gap: 6,
  radius: 10,
  opacity: 100,
  candH: 44,
  showCand: true,
  handleDocked: true,
  autoReload: true,
};

let state = Object.assign({}, DEFAULTS, JSON.parse(localStorage.getItem("inlineKeyboard-proto") || "{}"));
let shift = 0; // 0 = none, 1 = one-shot, 2 = locked
let fnActive = false;
let lastShiftTap = 0;

/* ---------------- 参数 → CSS ---------------- */
// 键盘宽高由用户定，键宽/键高全部由它们推导：
//   unit  = (宽 - 内边距 - 9 个间距) / 10   —— 每行 10 个单位
//   keyH  = (高 - 内边距 - 候选区 - 间距 - 把手条 - 行间距) / 行数
function applyParams() {
  const r = document.documentElement.style;
  const rows = window.ROWS[state.page] || window.ROWS.page1;
  const rowCount = rows.length;
  const handleVisible = state.mode === "floating" || state.handleDocked;
  const handleH = handleVisible ? 30 : 0;
  const pad = 8;
  const gap = state.gap;

  const unit = (state.kbW - pad * 2 - (UNITS - 1) * gap) / UNITS;
  const keyH = (state.kbH - pad * 2 - state.candH - gap - handleH - (rowCount - 1) * gap) / rowCount;

  r.setProperty("--units", UNITS);
  r.setProperty("--unit", unit.toFixed(2) + "px");
  r.setProperty("--key-h", Math.max(20, keyH).toFixed(2) + "px");
  r.setProperty("--gap", gap + "px");
  r.setProperty("--radius", state.radius + "px");
  r.setProperty("--cand-h", state.candH + "px");
  r.setProperty("--kb-opacity", state.opacity / 100);

  $("outKbW").textContent = state.kbW;
  $("outKbH").textContent = state.kbH;
  $("outGap").textContent = state.gap;
  $("outRadius").textContent = state.radius;
  $("outOpacity").textContent = state.opacity;
  $("outCand").textContent = state.candH;

  $("kbW").value = state.kbW;
  $("kbH").value = state.kbH;
  $("gap").value = state.gap;
  $("radius").value = state.radius;
  $("opacity").value = state.opacity;
  $("candH").value = state.candH;

  kbEl.classList.toggle("floating", state.mode === "floating");
  handlebarEl.classList.toggle("hidden", !handleVisible);

  for (const [id, val] of [["segMode", state.mode]]) {
    $(id).querySelectorAll("button").forEach((b) => b.classList.toggle("on", b.dataset.v === val));
  }

  $("readout").textContent =
    `键盘 ${state.kbW} × ${state.kbH}（占屏 ${((state.kbH / 800) * 100).toFixed(1)}%）\n` +
    `键 ${unit.toFixed(1)} × ${keyH.toFixed(1)} · ${rowCount} 行\n` +
    `候选 ${state.candH} · 把手条 ${handleH}`;

  localStorage.setItem("inlineKeyboard-proto", JSON.stringify(state));
}

/* ---------------- 键区渲染 ---------------- */
function renderKeys() {
  keysEl.innerHTML = "";
  const rows = window.ROWS[state.page] || window.ROWS.page1;

  rows.forEach((row, rowIndex) => {
    const rowEl = document.createElement("div");
    rowEl.className = "krow";
    // 第一行是常驻数字行
    const isNumRow = rowIndex === 0;
    if (isNumRow) rowEl.classList.add("numrow");

    row.forEach((key) => {
      const w = key.w || 1;
      const btn = document.createElement("button");
      btn.style.width = `calc(var(--unit) * ${w})`;

      // 占位键：占宽度，不响应
      if (key.k === "spacer") {
        btn.className = "key spacer";
        btn.tabIndex = -1;
        rowEl.appendChild(btn);
        return;
      }

      btn.className = "key";
      if (key.k === "key" || key.k === "shift" || key.k === "fn" || key.k === "stub")
        btn.classList.add("fn");
      if (key.k === "space") btn.classList.add("space");
      if (key.k === "stub") btn.classList.add("stub");
      if (isNumRow) btn.classList.add("num");
      if (key.k === "fn" && fnActive) btn.classList.add("on");
      // 小键上的长标签（如第二页的「第一页」）会自动缩字，避免竖排折行
      if (key.l && key.l.length >= 3 && w <= 1.2) btn.classList.add("small");

      // Fn 层：数字行变成 Esc / F1–F12
      const useFn = fnActive && key.fn;
      let label = useFn ? key.fn.l : key.l;
      if (key.k === "char" && shift > 0 && /^[a-z]$/i.test(label)) {
        label = label.toUpperCase();
        btn.classList.add("up");
      }
      if (key.k === "shift") {
        btn.classList.add("shift");
        if (shift === 2) btn.classList.add("lock");
        else if (shift === 1) btn.classList.add("on");
      }

      if (useFn) {
        btn.classList.add("fnlayer");
        btn.textContent = label;
      } else if (key.s) {
        // 真实键盘的双行键面：上档符号 + 下档字符
        btn.classList.add("dual");
        const top = document.createElement("span");
        top.className = "top";
        top.textContent = key.s;
        const bot = document.createElement("span");
        bot.className = "bot";
        bot.textContent = label;
        btn.appendChild(top);
        btn.appendChild(bot);
      } else {
        btn.textContent = label;
      }
      btn.title = useFn ? `keycode ${key.fn.c}` : key.c ? `keycode ${key.c}` : key.k;

      btn.addEventListener("click", () => onKey(key));
      rowEl.appendChild(btn);
    });

    keysEl.appendChild(rowEl);
  });
}

function onKey(key) {
  switch (key.k) {
    case "page":
      state.page = key.to;
      shift = 0;
      applyParams();
      renderKeys();
      break;
    case "shift": {
      const now = Date.now();
      if (now - lastShiftTap < 320) shift = shift === 2 ? 0 : 2;
      else shift = shift === 0 ? 1 : 0;
      lastShiftTap = now;
      renderKeys();
      break;
    }
    case "lang":
      // 原型里只是切换键面文字，真实实现是切 fcitx5 输入法
      key.l = key.l === "拼" ? "英" : "拼";
      renderKeys();
      break;
    case "char":
    case "key":
      if (shift === 1) {
        shift = 0;
        renderKeys();
      }
      flash(key);
      break;
    case "fn":
      fnActive = !fnActive;
      renderKeys();
      break;
    case "stub":
      // 集合子页还没做，先给个反馈
      preeditEl.textContent = key.l + " · 子页未实现";
      setTimeout(() => (preeditEl.textContent = "nihao"), 1000);
      break;
    default:
      flash(key);
  }
}

function flash(key) {
  preeditEl.textContent = key.l || "";
  setTimeout(() => {
    preeditEl.textContent = "nihao";
  }, 220);
}

/* ---------------- 候选区 ---------------- */
function renderCandbar() {
  const showCand = state.showCand;
  candsEl.innerHTML = "";

  if (showCand) {
    preeditEl.textContent = "nihao";
    candbarEl.querySelector(".shortcuts")?.remove();
    candsEl.style.display = "flex";
    window.FAKE_CANDS.forEach((text, i) => {
      const el = document.createElement("button");
      el.className = "cand";
      el.innerHTML = `<span class="idx">${i + 1}</span>${text}`;
      el.addEventListener("click", () => {
        preeditEl.textContent = "";
        setTimeout(() => (preeditEl.textContent = "nihao"), 400);
      });
      candsEl.appendChild(el);
    });
  } else {
    preeditEl.textContent = "";
    candsEl.style.display = "none";
    if (!candbarEl.querySelector(".shortcuts")) {
      const box = document.createElement("div");
      box.className = "shortcuts";
      window.FAKE_SHORTCUTS.forEach((s) => {
        const el = document.createElement("div");
        el.className = "shortcut";
        el.textContent = s;
        box.appendChild(el);
      });
      candbarEl.insertBefore(box, candsEl);
    }
  }
}

/* ---------------- 控件 ---------------- */
function bindRange(id, key) {
  $(id).addEventListener("input", (e) => {
    state[key] = Number(e.target.value);
    applyParams();
  });
}

["kbW", "kbH", "gap", "radius", "opacity", "candH"].forEach((id) =>
  bindRange(id, id)
);

$("segMode").addEventListener("click", (e) => {
  if (!e.target.dataset.v) return;
  state.mode = e.target.dataset.v;
  applyParams();
});

$("showCand").addEventListener("change", (e) => {
  state.showCand = e.target.checked;
  renderCandbar();
});

$("handleDocked").addEventListener("change", (e) => {
  state.handleDocked = e.target.checked;
  applyParams();
});

// 把手条两端：收起 / 语言切换（中间横条留给拖动）
$("hideBtn").addEventListener("click", () => {
  state.mode = "docked";
  applyParams();
});

$("langBtn").addEventListener("click", () => {
  const el = $("langBtn");
  el.textContent = el.textContent === "拼" ? "英" : "拼";
});

$("autoReload").addEventListener("change", (e) => {
  state.autoReload = e.target.checked;
  applyParams();
  watchReload();
});

$("copyBtn").addEventListener("click", async () => {
  const txt = JSON.stringify(
    { ...state, derived: $("readout").textContent },
    null,
    2
  );
  try {
    await navigator.clipboard.writeText(txt);
    $("copyBtn").textContent = "已复制 ✓";
  } catch {
    $("copyBtn").textContent = "复制失败，看 readout";
  }
  setTimeout(() => ($("copyBtn").textContent = "复制当前参数"), 1200);
});

/* ---------------- 自适应缩放 ---------------- */
const wrapEl = $("canvasWrap");
const stageEl = document.querySelector(".stage");

function fit() {
  const panelEl = document.querySelector(".panel");
  const pad = 32;
  const availW = window.innerWidth - (panelEl ? panelEl.offsetWidth : 0) - pad;
  const availH = window.innerHeight - pad;
  if (availW <= 0 || availH <= 0) return;
  const s = Math.min(availW / 1280, availH / 800);
  wrapEl.style.width = Math.round(1280 * s) + "px";
  wrapEl.style.height = Math.round(800 * s) + "px";
  screenEl.style.transform = `scale(${s.toFixed(4)})`;
}

window.addEventListener("resize", fit);

/* ---------------- 重新加载自己（文件改动后） ---------------- */
let lastModified = null;
let reloadTimer = null;

async function watchReload() {
  clearInterval(reloadTimer);
  if (!state.autoReload) return;
  try {
    const r = await fetch("index.html", { method: "HEAD", cache: "no-store" });
    lastModified = r.headers.get("last-modified");
  } catch {
    return;
  }
  reloadTimer = setInterval(async () => {
    if (!state.autoReload) return;
    try {
      const r = await fetch("index.html", { method: "HEAD", cache: "no-store" });
      const lm = r.headers.get("last-modified");
      if (lastModified && lm && lm !== lastModified) location.reload();
    } catch {}
  }, 1200);
}

/* ---------------- 启动 ---------------- */
applyParams();
renderKeys();
renderCandbar();
fit();
$("showCand").checked = state.showCand;
$("handleDocked").checked = state.handleDocked;
$("autoReload").checked = state.autoReload;
watchReload();
