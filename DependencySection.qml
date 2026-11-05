// 设置页顶部的依赖区：ydotoold（必需）/ fcitx5 addon（可选）/ 触控板后端（可选）。
//
// 三行共用 DependencyRow 一套视觉。状态全靠自己探测（3 秒一轮）——设置页拿不到 daemon
// 的运行时状态，addon 又是单客户端设计（连上去会把键盘顶掉），所以版本走 runtime dir 文件。

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Modules.Settings.Widgets
import qs.Services

Column {
    id: root

    width: parent ? parent.width : 0
    spacing: Theme.spacingL

    // ydotoold 状态：没有它什么键都发不出去，所以摆在最上面
    property bool ydotooldUp: true
    // 自启动状态和服务级别：状态行要显示「已启动 · 开机自启 · 用户级」三段
    property bool ydotooldEnabled: false
    // 安装命令默认折叠，点「展开命令」才显示
    property bool addonCmdExpanded: false
    property bool vtpadCmdExpanded: false

    // 两个后端的期望版本。后端把自己实际跑的版本写进 $XDG_RUNTIME_DIR/<x>.version，
    // 设置页读文件比对 —— 单客户端设计让设置页没法连 socket 去问。
    // 改这里要和 InlineKeyboardDaemon.qml 的 requiredAddonVersion 一起改。
    readonly property string requiredAddonVersion: "0.1.2"
    readonly property string requiredVtpadVersion: "0.1.0"
    property string addonInstalledVersion: ""
    property string vtpadInstalledVersion: ""
    // 只有拿到版本才谈得上「过期」；没拿到（老版本不写文件）当作不知道。
    // 按数值比较：装了更新的版本不该被提示「需要更新」
    function versionLessThan(installed, required) {
        if (!installed || !required)
            return false;

        const a = installed.split(".").map(Number);
        const b = required.split(".").map(Number);
        const n = Math.max(a.length, b.length);
        for (let i = 0; i < n; i++) {
            const x = a[i] || 0;
            const y = b[i] || 0;
            if (x !== y)
                return x < y;

        }
        return false;
    }
    readonly property bool addonOutdated: root.versionLessThan(root.addonInstalledVersion, root.requiredAddonVersion)
    readonly property bool vtpadOutdated: root.versionLessThan(root.vtpadInstalledVersion, root.requiredVtpadVersion)
    property string ydotooldLevel: "none"   // user / system / none

    // 触控板后端服务（可选，装在 systemd --user 下）。设置页直接管启停和开机自启。
    property bool helperUnitExists: false
    property bool helperActive: false
    property bool helperEnabled: false
    property bool helperBusy: false
    // 可选扩展：fcitx5 桥接
    // 装了 addon 才有候选、拼音串和地球键切换；没装也能打字（按键走 ydotool）
    property bool bridgeUp: false
    // 安装命令直接摆出来，省得用户回 README 找
    // 触控板后端（可选）：只装到用户目录，**不启用**（enable/start 由下面的按钮决定）。
    // unit 文件在仓库里（dms-vtpad-helper.service），ExecStart 用 %h 所以直接 cp 就行。
    // 更新命令：装过一版之后要拉新代码、重装、重启，跟首次安装不同
    readonly property string addonUpdateCommands: [
        "cd fcitx5-inline-keyboard-status && git pull",
        "cmake -B build -G Ninja && ninja -C build",
        "cmake --install build --prefix ~/.local",
        "systemctl --user restart 'app-org.fcitx.Fcitx5@autostart.service'"
    ].join("\n")

    readonly property string vtpadUpdateCommands: [
        "cd /tmp/dms-vtpad-helper && git pull && make",
        "install -m755 dms-vtpad-helper vtpadctl ~/.local/bin/",
        "cp dms-vtpad-helper.service ~/.config/systemd/user/",
        "systemctl --user daemon-reload",
        "systemctl --user restart dms-vtpad-helper.service"
    ].join("\n")

    readonly property string vtpadInstallCommands: [
        "git clone https://github.com/LilFishyChan/dms-vtpad-helper /tmp/dms-vtpad-helper",
        "cd /tmp/dms-vtpad-helper && make",
        "mkdir -p ~/.local/bin ~/.config/systemd/user",
        "install -m755 dms-vtpad-helper vtpadctl ~/.local/bin/",
        "cp dms-vtpad-helper.service ~/.config/systemd/user/",
        "systemctl --user daemon-reload"
    ].join("\n")
    readonly property string installCommands: "git clone https://github.com/LilFishyChan/fcitx5-inline-keyboard-status /tmp/fcitx5-inline-keyboard-status\n" + "cd /tmp/fcitx5-inline-keyboard-status && cmake -B build -G Ninja && ninja -C build\n" + "cmake --install build --prefix ~/.local\n" + "systemctl --user restart 'app-org.fcitx.Fcitx5@autostart.service'"

    // 触控板后端服务的状态刷新
    function refreshHelper() {
        helperProbe.running = true;
    }

    function helperAction(verb) {
        if (root.helperBusy)
            return ;

        root.helperBusy = true;
        helperCtl.command = ["systemctl", "--user", verb, "dms-vtpad-helper.service"];
        helperCtl.running = true;
    }

    // 服务/socket 状态会变（addon 重启会重建 socket、用户在外面启停服务），
    // 只靠打开设置页时探一次会一直显示旧状态
    Timer {
        interval: 3000
        repeat: true
        // 设置页不可见时停掉：平板上一路开着会每 3 秒起 4 个 shell
        running: root.visible
        onTriggered: {
            if (!daemonCheck.running)
                daemonCheck.running = true;

            if (!bridgeCheck.running)
                bridgeCheck.running = true;

            if (!versionCheck.running)
                versionCheck.running = true;

            if (!helperProbe.running)
                helperProbe.running = true;
        }
    }

    Process {
        id: daemonCheck

        running: false
        // 一次拿三个字段：进程在不在 / 是否开机自启 / 服务装在哪一级。
        // 进程用 pgrep 而不是 is-active：ydotoold 也常被手动拉起来，那时候没有 service。
        command: ["sh", "-c", 'P=$(pgrep -u "$(id -u)" -x ydotoold >/dev/null && echo running || echo stopped); if systemctl --user list-unit-files ydotool.service --no-legend 2>/dev/null | grep -q .; then L=user; E=$(systemctl --user is-enabled ydotool 2>/dev/null); elif systemctl list-unit-files ydotool.service --no-legend 2>/dev/null | grep -q .; then L=system; E=$(systemctl is-enabled ydotool 2>/dev/null); else L=none; E=disabled; fi; echo "$P|${E:-disabled}|$L"']
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split("|");
                root.ydotooldUp = (parts[0] || "") === "running";
                root.ydotooldEnabled = (parts[1] || "") === "enabled";
                root.ydotooldLevel = parts[2] || "none";
            }
        }
    }

    Process {
        id: daemonStart

        running: false
        command: ["systemctl", "--user", "start", "ydotool"]
        onExited: (code) => {
            if (code !== 0)
                ToastService.showError(I18n.trFor("inlineKeyboard", "Could not start ydotoold"));

            daemonCheck.running = true;
        }
    }

    Process {
        id: daemonDisable

        running: false
        // 级别不同要打到不同的 systemctl 上；退出码要透出来，否则失败时界面毫无反应
        command: ["sh", "-c", "systemctl --user disable ydotool 2>/dev/null || systemctl disable ydotool 2>/dev/null"]
        onExited: (code) => {
            if (code !== 0)
                ToastService.showError(I18n.trFor("inlineKeyboard", "Could not disable autostart"));

            daemonCheck.running = true;
        }
    }

    // 停 ydotoold：包成 service 的停 service，手动起的直接 kill —— 两种部署方式都覆盖
    Process {
        id: daemonStop

        running: false
        command: ["sh", "-c", "systemctl --user stop ydotool 2>/dev/null; pgrep -u \"$(id -u)\" -x ydotoold | xargs -r kill 2>/dev/null"]
        onExited: {
            daemonCheck.running = true;
        }
    }

    Process {
        id: daemonEnable

        running: false
        command: ["systemctl", "--user", "enable", "--now", "ydotool"]
        onExited: (code) => {
            if (code !== 0)
                ToastService.showError(I18n.trFor("inlineKeyboard", "Could not enable ydotoold"));

            daemonCheck.running = true;
        }
    }

    Process {
        id: bridgeCheck

        running: false
        // 和 daemonCheck 同理由：文件残留会误判，所以测的是 socket 本身
        command: ["sh", "-c", 'test -S "$XDG_RUNTIME_DIR/inline-keyboard.sock"']
        onExited: (code) => {
            return root.bridgeUp = (code === 0);
        }
    }

    // 复制到剪贴板：一个进程排队处理，成功/失败都有反馈（原来四个各写一遍、都不看退出码）
    property var copyQueue: []

    function copyText(text) {
        root.copyQueue = root.copyQueue.concat([text]);
        root.drainCopy();
    }

    function drainCopy() {
        if (copyProc.running || root.copyQueue.length === 0)
            return;

        const next = root.copyQueue[0];
        root.copyQueue = root.copyQueue.slice(1);
        copyProc.extraArgs = next;
        copyProc.running = true;
    }

    Process {
        id: copyProc

        property string extraArgs: ""

        running: false
        command: ["dms", "cl", "copy", copyProc.extraArgs]
        onExited: (code) => {
            if (code !== 0)
                ToastService.showError(I18n.trFor("inlineKeyboard", "Could not copy to clipboard"));

            root.drainCopy();
        }
    }

    // 两个后端各自把版本写进 runtime dir，一次读回来
    Process {
        id: versionCheck

        running: false
        command: ["sh", "-c", 'cat "$XDG_RUNTIME_DIR/inline-keyboard.version" 2>/dev/null; echo "@@"; cat "$XDG_RUNTIME_DIR/dms-vtpad.version" 2>/dev/null']
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split("@@");
                root.addonInstalledVersion = (parts[0] || "").trim();
                root.vtpadInstalledVersion = (parts[1] || "").trim();
            }
        }
    }


    Component.onCompleted: {
        daemonCheck.running = true;
        versionCheck.running = true;
        bridgeCheck.running = true;
        root.refreshHelper();
    }

    // ── 依赖 ────────────────────────────────────────────────────────
    // 三行同一套视觉：必需（ydotoold）、可选（fcitx5 addon）、可选（触控板后端）。
    // 每加一个外部依赖就在这里加一行，别再往页面里塞各写各的说明卡。
    SettingsSection {
        text: I18n.trFor("inlineKeyboard", "Dependencies")
    }

    SettingsGroup {
        width: parent.width
        slotColor: SettingsMetrics.paneColor

        DependencyRow {
            title: "ydotoold"

            // 三段式：已启动 / 已停止 · 开机自启 / 未开机自启 · 用户级 / 系统级 / 无服务
            stateText: {
                const run = root.ydotooldUp ? I18n.trFor("inlineKeyboard", "Started") : I18n.trFor("inlineKeyboard", "Not running");
                const auto = root.ydotooldEnabled ? I18n.trFor("inlineKeyboard", "autostart on") : I18n.trFor("inlineKeyboard", "autostart off");
                const lvl = root.ydotooldLevel === "user" ? I18n.trFor("inlineKeyboard", "user-level") : (root.ydotooldLevel === "system" ? I18n.trFor("inlineKeyboard", "system-level") : I18n.trFor("inlineKeyboard", "no service"));
                return run + " · " + auto + " · " + lvl;
            }
            stateOk: root.ydotooldUp
            buttons: {
                // 只对**用户级**服务给按钮：我们的操作全是 systemctl --user，
                // 管不到系统级 unit（那要 root），给了按钮也只是点了没反应。
                if (root.ydotooldLevel !== "user")
                    return [];

                const list = [];

                if (root.ydotooldUp)
                    list.push({
                        "text": I18n.trFor("inlineKeyboard", "Stop"),
                        "variant": "outlined",
                        "onClicked": function() {
                            daemonStop.running = true;
                        }
                    });
                else
                    list.push({
                        "text": I18n.trFor("inlineKeyboard", "Start"),
                        "variant": "filled",
                        "onClicked": function() {
                            daemonStart.running = true;
                        }
                    });

                if (root.ydotooldEnabled)
                    list.push({
                        "text": I18n.trFor("inlineKeyboard", "Disable autostart"),
                        "onClicked": function() {
                            daemonDisable.running = true;
                        }
                    });
                else
                    list.push({
                        "text": I18n.trFor("inlineKeyboard", "Enable at login"),
                        "onClicked": function() {
                            daemonEnable.running = true;
                        }
                    });

                return list;
            }
        }

        DependencyRow {
            title: I18n.trFor("inlineKeyboard", "Input method addon (fcitx5)")
            stateText: {
                const base = root.bridgeUp ? I18n.trFor("inlineKeyboard", "Connected — candidates, preedit and the globe switcher are live") : I18n.trFor("inlineKeyboard", "Not installed — the keyboard still types, but the candidate strip stays empty");
                if (!root.bridgeUp || root.addonInstalledVersion === "")
                    return base;

                // 版本对不上就说清楚「现在是多少、要多少」，别让用户猜
                if (root.addonOutdated)
                    return base + " · v" + root.addonInstalledVersion + " → v" + root.requiredAddonVersion + " " + I18n.trFor("inlineKeyboard", "needs update");

                return base + " · v" + root.addonInstalledVersion;
            }
            stateOk: root.bridgeUp && !root.addonOutdated
            buttons: root.bridgeUp && root.addonOutdated ? [{
                "text": I18n.trFor("inlineKeyboard", "Copy update commands"),
                "variant": "filled",
                "onClicked": function() {
                    root.copyText(root.addonUpdateCommands);
                }
            }, {
                "text": root.addonCmdExpanded ? I18n.trFor("inlineKeyboard", "Hide command") : I18n.trFor("inlineKeyboard", "Show command"),
                "onClicked": function() {
                    root.addonCmdExpanded = !root.addonCmdExpanded;
                }
            }] : root.bridgeUp ? [] : [{
                "text": I18n.trFor("inlineKeyboard", "Copy install commands"),
                "variant": "tonal",
                "onClicked": function() {
                    root.copyText(root.installCommands);
                }
            }, {
                "text": root.addonCmdExpanded ? I18n.trFor("inlineKeyboard", "Hide command") : I18n.trFor("inlineKeyboard", "Show command"),
                "onClicked": function() {
                    root.addonCmdExpanded = !root.addonCmdExpanded;
                }
            }]

            // 没装/过期才把命令摆在这一行里面，默认折叠
            CommandBlock {
                visible: (!root.bridgeUp || root.addonOutdated) && root.addonCmdExpanded
                commandText: root.addonOutdated ? root.addonUpdateCommands : root.installCommands
            }

        }

        DependencyRow {
            title: I18n.trFor("inlineKeyboard", "Touchpad backend")

            stateText: {
                if (!root.helperUnitExists)
                    return I18n.trFor("inlineKeyboard", "Not installed — the touchpad page stays disabled");

                const run = root.helperActive ? I18n.trFor("inlineKeyboard", "Started") : I18n.trFor("inlineKeyboard", "Not running");
                const auto = root.helperEnabled ? I18n.trFor("inlineKeyboard", "autostart on") : I18n.trFor("inlineKeyboard", "autostart off");
                let text = run + " · " + auto + " · " + I18n.trFor("inlineKeyboard", "user-level");

                if (root.vtpadInstalledVersion !== "") {
                    if (root.vtpadOutdated)
                        text += " · v" + root.vtpadInstalledVersion + " → v" + root.requiredVtpadVersion + " " + I18n.trFor("inlineKeyboard", "needs update");
                    else
                        text += " · v" + root.vtpadInstalledVersion;
                }

                return text;
            }
            stateOk: root.helperActive && !root.vtpadOutdated

            // 没装/过期才把命令摆在这一行里面，默认折叠
            CommandBlock {
                visible: (!root.helperUnitExists || root.vtpadOutdated) && root.vtpadCmdExpanded
                commandText: root.vtpadOutdated ? root.vtpadUpdateCommands : root.vtpadInstallCommands
            }

            buttons: root.helperUnitExists ? [{
                "text": root.helperActive ? I18n.trFor("inlineKeyboard", "Stop") : I18n.trFor("inlineKeyboard", "Start"),
                "variant": "filled",
                "enabled": !root.helperBusy,
                "onClicked": function() {
                    root.helperAction(root.helperActive ? "stop" : "start");
                }
            }, {
                "text": root.helperEnabled ? I18n.trFor("inlineKeyboard", "Disable autostart") : I18n.trFor("inlineKeyboard", "Enable autostart"),
                "variant": "outlined",
                "enabled": !root.helperBusy,
                "onClicked": function() {
                    root.helperAction(root.helperEnabled ? "disable" : "enable");
                }
            }, {
                "text": I18n.trFor("inlineKeyboard", "Copy update commands"),
                "variant": "filled",
                "visible": root.vtpadOutdated,
                "enabled": root.helperUnitExists,
                "onClicked": function() {
                    root.copyText(root.vtpadUpdateCommands);
                }
            }, {
                "text": root.vtpadCmdExpanded ? I18n.trFor("inlineKeyboard", "Hide command") : I18n.trFor("inlineKeyboard", "Show command"),
                "visible": root.vtpadOutdated,
                "onClicked": function() {
                    root.vtpadCmdExpanded = !root.vtpadCmdExpanded;
                }
            }] : [{
                "text": I18n.trFor("inlineKeyboard", "Copy install commands"),
                "variant": "tonal",
                "onClicked": function() {
                    root.copyText(root.vtpadInstallCommands);
                }
            }, {
                "text": root.vtpadCmdExpanded ? I18n.trFor("inlineKeyboard", "Hide command") : I18n.trFor("inlineKeyboard", "Show command"),
                "onClicked": function() {
                    root.vtpadCmdExpanded = !root.vtpadCmdExpanded;
                }
            }]
        }

    }

    // 一次调用拿齐三个状态：unit 名（空 = 没装）、is-active、is-enabled。
    // 分三次跑会闪，而且顺序不保证。
    Process {
        id: helperProbe

        command: ["sh", "-c", "U=$(systemctl --user list-unit-files dms-vtpad-helper.service --no-legend 2>/dev/null | head -1 | cut -d' ' -f1); A=$(systemctl --user is-active dms-vtpad-helper.service 2>/dev/null); E=$(systemctl --user is-enabled dms-vtpad-helper.service 2>/dev/null); echo \"${U:-none}|${A:-inactive}|${E:-disabled}\""]

        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split("|");
                root.helperUnitExists = (parts[0] || "none") !== "none";
                root.helperActive = (parts[1] || "") === "active";
                root.helperEnabled = (parts[2] || "") === "enabled";
            }
        }

    }

    Process {
        id: helperCtl

        onExited: {
            root.helperBusy = false;
            Qt.callLater(root.refreshHelper);
        }

    }

}
