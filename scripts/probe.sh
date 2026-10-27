#!/usr/bin/env bash
# 数据层自检 —— 不启动键盘 UI，直接验证 fcitx5 ↔ addon 这条链路。
#
# 用途：怀疑「候选不显示 / 输入法状态不对」时，先跑这个确认数据本身是否正常，
# 再去查 QML。UI 层的所有数据都来自这里产出的两个 JSON，它们对了，
# 问题就一定在 QML 侧。
#
#   ./scripts/probe.sh            看当前状态
#   ./scripts/probe.sh all        额外请求全量候选
#   ./scripts/probe.sh watch      每 500ms 刷新一次（Ctrl-C 退出）
#
# 退出码：0 全部正常；1 有问题（会打印具体哪一项）。

set -uo pipefail

RT="${XDG_RUNTIME_DIR:-/run/user/1000}"
STATUS="$RT/inline-keyboard-status.json"
ALLCAND="$RT/inline-keyboard-allcand.json"
FLAG="$RT/inline-keyboard-active"
EXPAND="$RT/inline-keyboard-expand"

c_ok=$'\033[32m'; c_bad=$'\033[31m'; c_dim=$'\033[2m'; c_off=$'\033[0m'
fail=0

check() { # check <描述> <命令...>
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        printf '  %s✓%s %s\n' "$c_ok" "$c_off" "$desc"
    else
        printf '  %s✗%s %s\n' "$c_bad" "$c_off" "$desc"
        fail=1
    fi
}

json_field() { # json_field <文件> <python 表达式，变量名 d>
    python3 - "$1" "$2" <<'PY' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print("")
    sys.exit(1)
try:
    v = eval(sys.argv[2])
except Exception:
    v = ""
print(v)
PY
}

show_status() {
    if [ ! -f "$STATUS" ]; then
        printf '  %s✗%s 状态文件不存在：%s\n' "$c_bad" "$c_off" "$STATUS"
        fail=1
        return
    fi

    printf '%s── 面板状态 ──%s\n' "$c_dim" "$c_off"
    printf '  im       %s\n' "$(json_field "$STATUS" 'd.get("im","")')"
    printf '  imlabel  %s\n' "$(json_field "$STATUS" 'd.get("imlabel","")')"
    printf '  imicon   %s\n' "$(json_field "$STATUS" 'd.get("imicon","")')"
    printf '  keyboard %s\n' "$(json_field "$STATUS" 'd.get("keyboard")')"
    printf '  preedit  %s\n' "$(json_field "$STATUS" 'repr(d.get("preedit",""))')"
    printf '  items    %s 个 %s\n' \
        "$(json_field "$STATUS" 'len(d.get("items") or [])')" \
        "$(json_field "$STATUS" '" ".join((d.get("items") or [])[:6])')"
    printf '  翻页     hasPrev=%s hasNext=%s\n' \
        "$(json_field "$STATUS" 'd.get("hasPrev")')" \
        "$(json_field "$STATUS" 'd.get("hasNext")')"
}

main() {
    local mode="${1:-}"

    printf '%s=== 链路自检 ===%s\n' "$c_dim" "$c_off"
    check "fcitx5 在运行" pgrep -x fcitx5
    check "addon 已加载" sh -c \
        "busctl --user call org.fcitx.Fcitx5 /controller org.fcitx.Fcitx.Controller1 GetAddons 2>/dev/null | grep -q inline-keyboard-status"
    check "键盘标志存在（$FLAG）" test -f "$FLAG"

    local ui
    ui=$(busctl --user call org.fcitx.Fcitx5 /controller \
        org.fcitx.Fcitx.Controller1 CurrentUI 2>/dev/null | sed 's/^s //')
    if [ "$(echo "$ui" | tr -d '"')" = "inline-keyboard-status" ]; then
        printf '  %s✓%s 当前 UI = inline-keyboard-status（候选由键盘接管）\n' "$c_ok" "$c_off"
    elif [ -f "$FLAG" ]; then
        printf '  %s✗%s 键盘开着但 UI = %s（没接管）\n' "$c_bad" "$c_off" "$ui"
        fail=1
    else
        printf '  %s✓%s 当前 UI = %s（键盘关着，classicui 接管，正常）\n' \
            "$c_ok" "$c_off" "$ui"
    fi

    echo
    show_status

    if [ "$mode" = "all" ]; then
        echo
        printf '%s── 全量候选 ──%s\n' "$c_dim" "$c_off"
        printf '1' > "$EXPAND"
        sleep 2
        if [ -f "$ALLCAND" ]; then
            printf '  共 %s 个\n' "$(json_field "$ALLCAND" 'len(d)')"
            printf '  前10 %s\n' "$(json_field "$ALLCAND" '" ".join(d[:10])')"
            printf '  末5  %s\n' "$(json_field "$ALLCAND" '" ".join(d[-5:])')"
        else
            printf '  %s✗%s 没生成 %s\n' "$c_bad" "$c_off" "$ALLCAND"
            fail=1
        fi
    fi

    echo
    if [ "$fail" -eq 0 ]; then
        printf '%s数据层正常%s\n' "$c_ok" "$c_off"
    else
        printf '%s数据层有问题（见上面 ✗ 项）%s\n' "$c_bad" "$c_off"
    fi
    return "$fail"
}

case "${1:-}" in
    watch)
        while true; do clear; show_status; sleep 0.5; done
        ;;
    *)
        main "$@"
        ;;
esac
