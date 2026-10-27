#!/bin/sh
# 预览用的静态服务（local only）。由 systemd --user 的 inlineKeyboard-preview unit 拉起：
#   systemd-run --user --unit=inlineKeyboard-preview --working-directory=<本目录> --collect ./serve.sh
exec python3 serve.py
