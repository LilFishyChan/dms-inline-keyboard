#!/usr/bin/env python3
"""inlineKeyboard addon 数据层测试工具。

直接连 addon 的 Unix socket，验证它给出的候选数据是否正确 ——
不经过任何 QML / UI，输出就是 addon 的真实数据。

用法：
    ./scripts/test-addon.py state           # 当前状态（preedit / 候选数 / 输入法）
    ./scripts/test-addon.py all             # 请求全量候选并全部打印
    ./scripts/test-addon.py all --limit 30  # 只打印前 30 个
    ./scripts/test-addon.py type            # 自己注入 c e 再拉全量（不依赖键盘）
    ./scripts/test-addon.py type n i        # 注入指定的键
    ./scripts/test-addon.py watch           # 持续打印状态推送（调试用）

判据：全量里的前 N 个必须和 state 里的 items 完全一致 ——
它们来自同一个 context、同一份候选表。
"""

import argparse
import json
import os
import socket
import sys
import time

SOCKET_NAME = "inline-keyboard.sock"


def socket_path() -> str:
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime_dir:
        sys.exit("需要设置 XDG_RUNTIME_DIR")
    return os.path.join(runtime_dir, SOCKET_NAME)


class AddonClient:
    """addon 的 socket 客户端。

    addon 只接受一个客户端（单客户端设计），所以这个工具运行期间
    键盘插件连不上。测完记得关掉。
    """

    def __init__(self, timeout=3.0):
        self.path = socket_path()
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(timeout)
        try:
            self.sock.connect(self.path)
        except (FileNotFoundError, ConnectionRefusedError) as error:
            sys.exit(f"连不上 {self.path}: {error}\naddon 在跑吗？")
        self.buffer = b""

    def send(self, line: str) -> bool:
        """发一行。addon 只有一个客户端槽位，被顶掉时会断开，这里不抛异常。"""
        try:
            self.sock.sendall((line + "\n").encode())
            return True
        except (BrokenPipeError, ConnectionResetError, OSError):
            return False

    def read_lines(self, duration: float) -> list[str]:
        """在 duration 秒内收到的所有完整行。"""
        deadline = time.monotonic() + duration
        lines = []
        while time.monotonic() < deadline:
            self.sock.settimeout(max(0.05, deadline - time.monotonic()))
            try:
                chunk = self.sock.recv(65536)
            except socket.timeout:
                break
            if not chunk:
                break
            self.buffer += chunk
            while b"\n" in self.buffer:
                raw, self.buffer = self.buffer.split(b"\n", 1)
                lines.append(raw.decode("utf-8", "replace"))
        return lines

    def close(self) -> None:
        self.sock.close()


def parse_state(lines: list[str]) -> dict | None:
    """取最后一条 state: 推送。"""
    state = None
    for line in lines:
        if line.startswith("state:"):
            try:
                state = json.loads(line[6:])
            except json.JSONDecodeError:
                continue
    return state


def parse_allcand(lines: list[str]) -> list[dict] | None:
    """取最后一条 allcand: 推送，返回 [{i, t}, ...]。"""
    for line in reversed(lines):
        if not line.startswith("allcand:"):
            continue
        try:
            raw = json.loads(line[8:])
        except json.JSONDecodeError:
            continue
        if not isinstance(raw, list):
            return None
        words = []
        for index, item in enumerate(raw):
            if isinstance(item, dict):
                words.append({"i": item.get("i", index), "t": item.get("t", "")})
            else:
                words.append({"i": index, "t": str(item)})
        return words
    return None


def cmd_state(args) -> int:
    client = AddonClient()
    try:
        lines = client.read_lines(0.8)
    finally:
        client.close()
    state = parse_state(lines)
    if state is None:
        print("没收到 state 推送")
        return 1
    print(f"preedit   = {state.get('preedit', '')!r}")
    print(f"im        = {state.get('im', '')} / {state.get('imlabel', '')}"
          f"   keyboard={state.get('keyboard')}")
    print(f"items     = {len(state.get('items') or [])} 个")
    print(f"hasMore   = {state.get('hasMore')}")
    items = state.get("items") or []
    if items:
        print(f"items[:10]= {items[:10]}")
    return 0


def cmd_all(args) -> int:
    client = AddonClient()
    try:
        # 先等一条 state，确认 addon 活着
        first = client.read_lines(0.6)
        state = parse_state(first)
        client.send("expand")
        words = parse_allcand(client.read_lines(2.0))
    finally:
        client.close()

    if words is None:
        print("没收到 allcand 推送")
        return 1

    print(f"总数      = {len(words)}")
    if state is not None:
        items = state.get("items") or []
        print(f"preedit   = {state.get('preedit', '')!r}")
        print(f"items     = {len(items)} 个")
        # 一致性检查：全量前 len(items) 个应当和 items 完全一致
        head = [word["t"] for word in words[:len(items)]]
        if items and head == items:
            print("一致性    = ✓ 全量前段与 items 完全一致")
        elif not items:
            print("一致性    = （items 为空，跳过）")
        else:
            print("一致性    = ✗ 不一致")
            print(f"  items   = {items[:8]}")
            print(f"  all[:{len(items)}] = {head[:8]}")

    # 下标连续性：去重/过滤后不得出现空洞
    indices = [word["i"] for word in words]
    if indices == list(range(len(indices))):
        print("下标      = ✓ 连续 0..N-1")
    else:
        gaps = [
            (previous, current)
            for previous, current in zip(indices, indices[1:])
            if current != previous + 1
        ]
        print(f"下标      = ✗ 不连续，跳变 {len(gaps)} 处，前 3 处 {gaps[:3]}")

    duplicates = len(words) - len({word["t"] for word in words})
    print(f"重复词    = {duplicates} 个")

    limit = args.limit if args.limit and args.limit > 0 else len(words)
    print(f"\n前 {min(limit, len(words))} 个：")
    for word in words[:limit]:
        print(f"  [{word['i']:4d}] {word['t']}")
    return 0


def cmd_type(args) -> int:
    """自己注入按键产生候选，再拉全量。

    这样不依赖键盘插件占着 socket，也能验证 addon 的完整链路：
    key -> rime -> candidateList -> allcand。
    """
    keys = args.keys or ["c", "e"]
    client = AddonClient()
    try:
        client.read_lines(0.3)          # 吃掉连上时的快照
        # addon 不认 im: 命令（切输入法走 D-Bus），这里只注入按键
        for key in keys:
            if not client.send(f"key:{key}"):
                print(f"addon 断开了（注入 {key} 时）")
                return 1
            time.sleep(0.45)
        lines = client.read_lines(1.5)
        state = parse_state(lines)
        client.send("expand")
        words = parse_allcand(client.read_lines(2.0))
    finally:
        client.close()

    print("=== 输入后的状态 ===")
    if state is None:
        print("没收到 state")
    else:
        print(f"preedit = {state.get('preedit', '')!r}")
        print(f"im      = {state.get('im', '')} / {state.get('imlabel', '')}")
        items = state.get("items") or []
        print(f"items   = {len(items)} 个  {items[:10]}")

    print("\n=== 全量候选 ===")
    if words is None:
        print("没收到 allcand")
        return 1
    print(f"总数 = {len(words)}")
    limit = args.limit if args.limit and args.limit > 0 else 15
    for word in words[:limit]:
        print(f"  [{word['i']:4d}] {word['t']}")
    if len(words) > limit:
        print(f"  … 还有 {len(words) - limit} 个")
    return 0


def cmd_watch(args) -> int:
    client = AddonClient()
    print("持续监听（Ctrl-C 退出）…")
    try:
        while True:
            for line in client.read_lines(0.5):
                if not line.startswith("state:"):
                    continue
                state = json.loads(line[6:])
                items = state.get("items") or []
                print(f"pe={state.get('preedit', '')!r:20} "
                      f"items={len(items):3d} {items[:5]}")
    except KeyboardInterrupt:
        print()
    finally:
        client.close()
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="inlineKeyboard addon 数据层测试")
    parser.add_argument("command", choices=["state", "all", "type", "watch"])
    parser.add_argument("keys", nargs="*", help="type 命令要注入的键，默认 c e")
    parser.add_argument("--limit", type=int, default=0)
    args = parser.parse_args()
    handlers = {"state": cmd_state, "all": cmd_all, "type": cmd_type,
                "watch": cmd_watch}
    return handlers[args.command](args)


if __name__ == "__main__":
    sys.exit(main())
