// 和 dms-vtpad-helper 的 socket 客户端。
// 只做一件事：把触控板页的触摸事件转成 helper 的文本协议行。
//
// 这个 socket 是只发的（helper 不回话），但 Quickshell 的 Socket 不设 parser
// 就永远不触发读，所以挂一个空 SplitParser 占位。

import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: bridge

    // 插件活着就一直连着，断了自动重连（helper 没装时就是一直重试，开销可忽略）
    property bool enabled: true
    // 手势区的实际尺寸（逻辑像素），由 TouchpadSurface 报上来
    property int panelW: 0
    property int panelH: 0
    // 屏幕 DPI（逻辑像素/毫米）。平板 914×1462 逻辑 / 148×236mm ≈ 6.18
    property real pxPerMm: 6.18
    property int reconnectDelay: 500
    // 最近一次收到 pong 的时间；0 = 还没收到过
    property double lastPongAt: 0

    // 缺失时不回退 /tmp：世界可写目录，别的用户能抢先绑定 socket
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
    readonly property string socketPath: runtimeDir === "" ? "" : runtimeDir + "/dms-vtpad.sock"
    // 后端是否可用 = socket 连着（helper 在跑且接受了连接）
    readonly property bool up: socket.connected

    function send(line) {
        if (!socket.connected || bridge.socketPath === "")
            return false;

        socket.write(String(line).replace(/[\r\n]/g, " ") + "\n");
        return true;
    }

    // 面板尺寸变了要重发 hello：helper 侧的 ABS 范围在设备创建后改不了，
    // 它收到新的 hello 会销毁重建。
    function setPanel(w, h) {
        const nw = Math.max(1, Math.round(w));
        const nh = Math.max(1, Math.round(h));
        if (nw === bridge.panelW && nh === bridge.panelH)
            return;

        bridge.panelW = nw;
        bridge.panelH = nh;
        bridge.sendHello();
    }

    function sendHello() {
        if (bridge.panelW <= 0 || bridge.panelH <= 0)
            return false;

        return bridge.send("hello " + bridge.panelW + " " + bridge.panelH + " " + bridge.pxPerMm.toFixed(2));
    }

    Socket {
        id: socket

        path: bridge.socketPath
        parser: SplitParser {
            splitMarker: "\n"
            onRead: (data) => {
                // helper 只回 pong（心跳），其它忽略
                if (String(data).trim() === "pong")
                    bridge.lastPongAt = Date.now();
            }
        }
    }

    // 心跳：helper 重启会 unlink+bind 新的 socket 文件，旧连接在 ss 里还是 ESTAB、
    // Quickshell 也还认为 connected，但写进去的数据没人收 —— 表现是「走 fcitx 的键正常、
    // 走 helper 的键全哑」。只有真收到 pong 才能证明连接是活的。
    Timer {
        id: heartbeat

        interval: 1000
        repeat: true
        running: socket.connected
        onTriggered: {
            bridge.send("ping");
            if (bridge.lastPongAt > 0 && Date.now() - bridge.lastPongAt > 3000) {
                console.warn("[TouchpadBridge] 连接假活，强制重连");
                bridge.lastPongAt = 0;
                bridge.reconnectDelay = 500;
                socket.connected = false;
            }
        }
    }

    Timer {
        id: reconnectTimer

        interval: bridge.reconnectDelay
        // 连上了就不跑
        running: bridge.enabled && bridge.socketPath !== "" && !socket.connected
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            socket.connected = true;
            // 退避：helper 没起来时别每 500ms 敲一次
            bridge.reconnectDelay = Math.min(Math.round(bridge.reconnectDelay * 1.6), 4000);
        }
    }

    Connections {
        function onConnectedChanged() {
            if (!socket.connected) {
                bridge.lastPongAt = 0;
                return;
            }

            bridge.reconnectDelay = 500;
            // 给心跳留 3 秒宽限期，避免刚连上就被判成假活
            bridge.lastPongAt = Date.now();
            // 连上立刻握手：helper 没收到 hello 不会建设备
            Qt.callLater(bridge.sendHello);
        }

        target: socket
    }
}
