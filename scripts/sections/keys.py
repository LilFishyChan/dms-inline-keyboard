#!/usr/bin/env python3
"""keys 块：键位数据、按键点击、注入输出、页面键、修饰键档位。

核心是「遍历」：把当前页所有可点的键按顺序点一遍（干跑模式，不真发），
再拿注入记录和 layouts/phone.js 里算出的期望逐条比对。
这样能同时抓出：显示与输入不一致、键码接错、键位漏渲染。
"""

import re
import time

from . import common as c

# 非「可点字符键」的类型：修饰键 / 页面键 / 占位
SKIP_KINDS = {"spacer", "shift", "fn", "page", "mod"}
# 这些看着是 k:"key"，但点下去只切修饰状态、不注入键码（由 mods 子块单独验）
MODIFIER_LABELS = {"Caps Lock", "Ctrl", "Win", "Super", "Alt", "Shift", "Fn", "Meta"}
# 按住会重复发键的键（长按守卫用）
REPEATABLE = ("Backspace", "Del", "Home", "End", "PgUp", "PgDn", "Delete")


def tappable(kind, label):
    return kind not in SKIP_KINDS and bool(label) and label not in MODIFIER_LABELS
TAP_HOLD = 40  # 点击按住时长（ms）


def key_view(k, esc_swap):
    """一个键当前该显示什么、注入什么（主层 + Fn 层）。

    escSwap 只动「主层是 ~ 的那个 char 键」，并且是把主层和 Fn 层对调
    （和 data.js 的 swapEscTilde 一致）；page2 上真正的 Esc 键不受影响。
    """
    kind = k.get("k", "")
    fn = k.get("fn") or {}
    if esc_swap and kind == "char" and k.get("c", -1) == 41:
        return {"label": "Esc", "code": 1, "fn_label": "`", "fn_code": 41}
    label = k.get("l", "")
    # 字母：主层显示小写（大写得按 Shift，由上层 upperMode 决定）
    if kind == "char" and len(label) == 1 and label.isalpha():
        label = label.lower()
    return {"label": label, "code": k.get("c", -1),
            "fn_label": fn.get("l", ""), "fn_code": fn.get("c", -1)}


def expected_keys(page, esc_swap):
    """从布局数据算期望：只有可点的字符 / 功能 / 空格键。"""
    out = []
    for k in c.page_keys(page):
        kind = k.get("k", "")
        label = k.get("l", "")
        if not tappable(kind, label):
            continue
        view = key_view(k, esc_swap)
        out.append({"label": view["label"], "code": view["code"], "kind": kind})
    return out


def tappable_rendered(page):
    """渲染侧：同样规则过滤后的键表（带 repeater 下标）。"""
    out = []
    for item in c.render_keys(page):
        if not tappable(item["kind"], item["label"]):
            continue
        out.append(item)
    return out


def guard_for(rendered, tag):
    """按当前页挑守卫用键：一个普通键 + 一个可重复键，然后跑守卫。"""
    first = next((i["index"] for i in rendered
                  if i["kind"] == "char" and len(i["label"]) == 1), None)
    if first is None:
        first = next((i["index"] for i in rendered if i["kind"] == "char"), None)
    if first is None:
        first = next((i["index"] for i in rendered if i["label"] not in REPEATABLE), None)
    repeat = next((i["index"] for i in rendered if i["label"] in REPEATABLE), None)
    if first is None or repeat is None:
        c.check("%s: 找得到守卫用的键" % tag, False, "普通=%s 可重复=%s" % (first, repeat))
        raise SystemExit("找不到守卫用的键，中止（一个键都没点）")
    c.guard_dry_run(first, repeat)


def tap_all(rendered):
    """点一遍给定键表，返回 (注入记录, 没点成的键)。

    每次点击都要等它真正走完（干跑记录 +1）才点下一个 ——
    连发会把上一次的 release 吃掉，可重复键的长按定时器就停不下来。
    调用前必须已经开好干跑、清好记录。
    """
    failed = []
    for item in rendered:
        before = c.injected_count()
        r = c.ipc("debugTap", "keyAt", item["index"], TAP_HOLD)
        if "TAP:index" not in r:
            failed.append((item["index"], item["label"], r))
            continue
        for _ in range(30):
            time.sleep(0.04)
            if c.injected_count() > before:
                break
        else:
            failed.append((item["index"], item["label"], "没有干跑记录"))
    time.sleep(0.25)
    return c.injected(), failed


def walk(page, esc_swap):
    """点一遍该页所有可点键，返回 (渲染键表, 注入记录, 没点成的键)。

    每次点击都要等它真正走完（干跑记录 +1）才点下一个 ——
    连发会把上一次的 release 吃掉，可重复键的长按定时器就停不下来。
    """
    rendered = tappable_rendered(page)

    # 守卫：先证明拦截生效，再动真的
    # 守卫用键要现找：page1 有字母和 Backspace，page2 只有 F 区
    letter = next((i["index"] for i in rendered
                   if i["kind"] == "char" and len(i["label"]) == 1), None)
    if letter is None:
        letter = next((i["index"] for i in rendered if i["kind"] == "char"), None)
    if letter is None:
        letter = next((i["index"] for i in rendered if i["label"] not in REPEATABLE), None)
    repeat = next((i["index"] for i in rendered if i["label"] in REPEATABLE), None)
    if letter is None or repeat is None:
        c.check("%s: 找得到守卫用的键" % page, False,
                "letter=%s repeat=%s" % (letter, repeat))
        raise SystemExit("找不到守卫用的键（字母 / Backspace），中止")
    c.guard_dry_run(letter, repeat)

    c.dry_run(True)
    c.clear_injected()
    recs, failed_taps = tap_all(rendered)
    c.dry_run(False)
    c.clear_injected()
    return rendered, recs, failed_taps


def diff_report(mismatch, limit=8):
    return ", ".join(mismatch[:limit]) + (" …" if len(mismatch) > limit else "")


def run_page(page, title):
    """一整页：数量 → 标签 → 键码 → 注入记录逐条对齐。"""
    esc_swap = c.esc_swap_enabled()
    exp = expected_keys(page, esc_swap)
    rendered, recs, failed_taps = walk(page, esc_swap)

    c.check("%s: 可点键数（渲染 %d / 数据 %d）" % (title, len(rendered), len(exp)),
            len(rendered) == len(exp),
            "渲染 %d 数据 %d" % (len(rendered), len(exp)))
    if not c.check("%s: 每个键都点到了" % title, not failed_taps,
                   "点不到: " + diff_report(["%d/%s→%s" % t for t in failed_taps])):
        return

    # 标签与键码：渲染 vs 数据
    label_bad, code_bad = [], []
    for got, want in zip(rendered, exp):
        if got["label"] != want["label"]:
            label_bad.append("%d:%r≠%r" % (got["index"], got["label"], want["label"]))
        if got["code"] != want["code"]:
            code_bad.append("%s:%d≠%d" % (got["label"], got["code"], want["code"]))
    c.check("%s: 渲染标签 == 数据标签" % title, not label_bad, diff_report(label_bad))
    c.check("%s: 渲染键码 == 数据键码" % title, not code_bad, diff_report(code_bad))

    # 注入记录：数量 + 标签 + 键码
    c.check("%s: 注入记录数 == 点击数（%d/%d）" % (title, len(recs), len(rendered)),
            len(recs) == len(rendered),
            "记录 %d 点击 %d" % (len(recs), len(rendered)))
    inj_label, inj_code = [], []
    for got, want in zip(recs, exp):
        if got["label"].lower() != want["label"].lower():
            inj_label.append("%r→%r" % (want["label"], got["label"]))
        if got["code"] != want["code"]:
            inj_code.append("%s:%d≠%d" % (want["label"], got["code"], want["code"]))
    c.check("%s: 注入标签 == 期望标签" % title, not inj_label, diff_report(inj_label))
    c.check("%s: 注入键码 == 期望键码" % title, not inj_code, diff_report(inj_code))

    # 控制键一律走 ydotool（字符键的路由取决于输入法状态，不在这里断言）
    wrong_route = []
    for got, want in zip(recs, exp):
        if want["kind"] == "key" and got["route"] != "ydotool":
            wrong_route.append("%s→%s" % (want["label"], got["route"]))
    c.check("%s: 功能键走 ydotool" % title, not wrong_route, diff_report(wrong_route))


def page1():
    print("== keys:p1 遍历 page1 ==")
    c.ipc("setPage", "page1")
    time.sleep(0.4)
    run_page("page1", "p1")


def page2():
    print("== keys:p2 遍历 page2 ==")
    c.ipc("setPage", "page2")
    time.sleep(0.4)
    run_page("page2", "p2")
    c.ipc("setPage", "page1")  # 收尾：回到主键区，别把第二页状态留给下一块


def layers():
    """Fn 层 / Shift 层：把该页所有可点键再遍历一遍，期望按当前生效层算。

    层状态用 setModifier 直接摆成锁定（1 是软激活，普通键按一下就清）——
    真正的「点修饰键切换」由 keys:mods 子块验。
    """
    print("== keys:layer Fn / Shift 层 ==")
    c.ipc("setPage", "page1")
    time.sleep(0.4)
    esc = c.esc_swap_enabled()
    guard_for(tappable_rendered("page1"), "layer")

    # --- Fn 层：有 fn 的键切到 fn.l / fn.c，没有的保持主层 ---
    c.ipc("setModifier", "fn", 2)
    time.sleep(0.45)
    exp = []
    for k in c.page_keys("page1"):
        if not tappable(k.get("k", ""), k.get("l", "")):
            continue
        view = key_view(k, esc)
        if view["fn_label"]:
            exp.append({"label": view["fn_label"], "code": view["fn_code"]})
        else:
            exp.append({"label": view["label"], "code": view["code"]})
    rendered = tappable_rendered("page1")
    c.check("layer: Fn 层键数（渲染 %d / 数据 %d）" % (len(rendered), len(exp)),
            len(rendered) == len(exp), "渲染 %d 数据 %d" % (len(rendered), len(exp)))
    bad = [("%r≠%r" % (g["label"], w["label"]))
           for g, w in zip(rendered, exp) if g["label"] != w["label"]]
    c.check("layer: Fn 层渲染标签 == fn.l", not bad, diff_report(bad))
    bad = [("%r:%d≠%d" % (g["label"], g["code"], w["code"]))
           for g, w in zip(rendered, exp) if g["code"] != w["code"]]
    c.check("layer: Fn 层渲染键码 == fn.c", not bad, diff_report(bad))

    c.dry_run(True)
    c.clear_injected()
    recs, failed = tap_all(rendered)
    c.dry_run(False)
    c.clear_injected()
    c.check("layer: Fn 层每个键都点到了", not failed, diff_report(["%d/%s" % f for f in failed]))
    bad = [("%r/%d≠%r/%d" % (g["label"], g["code"], w["label"], w["code"]))
           for g, w in zip(recs, exp) if g["label"] != w["label"] or g["code"] != w["code"]]
    c.check("layer: Fn 层注入 == 期望（%d 条）" % len(recs),
            not bad and len(recs) == len(exp), diff_report(bad))
    c.ipc("setModifier", "fn", 0)
    time.sleep(0.35)

    # --- Shift 层：字母变大写、带 shift 变体的键切到变体，其余不变 ---
    c.ipc("setModifier", "shift", 2)
    time.sleep(0.45)
    exp = []
    for k in c.page_keys("page1"):
        if not tappable(k.get("k", ""), k.get("l", "")):
            continue
        view = key_view(k, esc)
        label, code = view["label"], view["code"]
        if k.get("shift"):
            label, code = k["shift"]["l"], k["shift"].get("c", code)
        elif len(label) == 1 and label.isalpha():
            label = label.upper()
        exp.append({"label": label, "code": code})
    rendered = tappable_rendered("page1")
    bad = [("%r≠%r" % (g["label"], w["label"]))
           for g, w in zip(rendered, exp) if g["label"] != w["label"]]
    c.check("layer: Shift 层渲染标签 == 上档/变体", not bad, diff_report(bad))

    c.dry_run(True)
    c.clear_injected()
    recs, failed = tap_all(rendered)
    c.dry_run(False)
    c.clear_injected()
    c.check("layer: Shift 层每个键都点到了", not failed, diff_report(["%d/%s" % f for f in failed]))
    bad = [("%r/%d≠%r/%d" % (g["label"], g["code"], w["label"], w["code"]))
           for g, w in zip(recs, exp) if g["label"] != w["label"] or g["code"] != w["code"]]
    c.check("layer: Shift 层注入 == 期望（%d 条）" % len(recs),
            not bad and len(recs) == len(exp), diff_report(bad))
    c.ipc("setModifier", "shift", 0)
    time.sleep(0.35)

    c.ipc("setPage", "page1")


# ---- 页面键 ----

def _page_state_is(n):
    return re.search(r"\bpage=%d\b" % n, c.diag()) is not None


def pages():
    """切页 + 页面键：page1 ↔ page2，含 modifierMode 四档下的状态值。"""
    print("== keys:page 页面键 ==")
    c.check("setPage page2 生效", c.ipc("setPage", "page2").endswith("page2"))
    c.check("diag 跟着切页", "page=page2" in c.diag(), c.diag()[:120])
    c.ipc("setPage", "page1")
    c.check("setPage page1 生效", "page=page1" in c.diag(), c.diag()[:120])

    r = c.ipc("debugTap", "key", "layers", 40)
    c.check("点页面键（icon=layers）", "TAP:layers" in r, r)
    time.sleep(0.5)
    c.check("点页面键进第二页", "page=page2" in c.diag(), c.diag()[:120])
    c.ipc("debugKey", "page", "page1")
    time.sleep(0.5)
    c.check("返回第一页", "page=page1" in c.diag(), c.diag()[:120])
    c.check("页面键状态清零", _page_state_is(0), c.diag()[:120])

    # 四档下「单击页面键」都该进第二页，区别只在状态值：
    # noLock / tapLock 直接锁定(2)，toggle / doubleTapLock 是一次性(1)
    for mode, state in (("noLock", 2), ("tapLock", 2), ("toggle", 1), ("doubleTapLock", 1)):
        c.ipc("setModifierMode", mode)
        c.ipc("setPage", "page1")
        time.sleep(0.35)
        c.ipc("debugTap", "key", "layers", 40)
        time.sleep(0.4)
        c.check(mode + "：单击进第二页", "page=page2" in c.diag(), c.diag()[:120])
        c.check("%s：状态应为 page=%d" % (mode, state), _page_state_is(state), c.diag()[:120])
        c.ipc("setPage", "page1")
    c.ipc("setModifierMode", "doubleTapLock")
    c.ipc("setPage", "page1")
    time.sleep(0.3)


# ---- 修饰键 ----

def _mod_state(name):
    m = re.search(r"\b" + name + r"=(\d+)", c.diag())
    return int(m.group(1)) if m else -1


def index_of(rendered, label):
    return next((i["index"] for i in rendered if i["label"].lower() == label.lower()), None)


def mods():
    """修饰键：四档切换 + 点修饰键只切状态、不注入键码。"""
    print("== keys:mods 修饰键 ==")
    for mode in ("noLock", "toggle", "tapLock", "doubleTapLock"):
        r = c.ipc("setModifierMode", mode)
        c.check("切到 " + mode, mode in r, r)
        c.check("  · 插件仍 loaded", c.plugin_status() == "loaded", c.plugin_status())
    c.ipc("setModifierMode", "doubleTapLock")
    time.sleep(0.3)

    rendered = c.render_keys("page1")
    for label, key in (("Caps Lock", "caps"), ("Ctrl", "ctrl"), ("Alt", "alt"), ("Win", "super")):
        idx = index_of(rendered, label)
        if idx is None:
            c.check("找得到 %s 键" % label, False, label)
            continue
        c.ipc("setModifier", key, 0)
        c.clear_injected()
        c.dry_run(True)
        r = c.ipc("debugTap", "keyAt", idx, 40)
        time.sleep(0.45)
        recs = c.injected()
        c.dry_run(False)
        c.clear_injected()
        c.check("点 %s 被受理" % label, "TAP:index" in r, r)
        c.check("点 %s → 不注入任何键码" % label, len(recs) == 0, recs)
        c.check("点 %s → %s 状态切了" % (label, key), _mod_state(key) != 0,
                "%s=%s" % (key, _mod_state(key)))
        c.ipc("setModifier", key, 0)
        time.sleep(0.2)


# ---- 干跑 ----

def dry():
    """干跑：记录「本来会发什么」，但一条都不真的发到系统。"""
    print("== keys:dry 干跑拦截 ==")
    base = c.addon_key_count()
    c.check("拿得到 addon 计数", base >= 0, base)

    rendered = c.render_keys("page1")
    c.dry_run(True)
    c.clear_injected()
    targets = [("a", "字母"), ("1", "数字"), ("Enter", "回车"), ("Backspace", "退格")]
    tapped = 0
    for label, name in targets:
        idx = index_of(rendered, label)
        if idx is None:
            c.check("找得到 %s 键" % name, False, label)
            continue
        c.ipc("debugTap", "keyAt", idx, 40)
        time.sleep(0.18)
        tapped += 1
    time.sleep(0.4)
    recs = c.injected()
    c.dry_run(False)
    c.clear_injected()

    c.check("干跑记下了 %d 条" % tapped, len(recs) == tapped, recs)
    c.check("addon 一条都没发出去", c.addon_key_count() == base,
            "%d → %d" % (base, c.addon_key_count()))
    bad = [r["label"] for r in recs if r["kind"] == "key" and r["route"] != "ydotool"]
    c.check("控制键（回车/退格）走 ydotool", not bad, bad)
    c.check("记录里带着选路信息", all(r["route"] for r in recs), recs)
