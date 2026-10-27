// 插件启用前的依赖检查。
// 数据来自 fcitx5 的 inline-keyboard-status addon（进程内，能用 BulkCandidateList
// 一次取出全部候选，也负责推送状态/输入法清单）；按键注入走 ydotool
// （真实 uinput 设备）；切输入法同样走 addon 的 im: 指令。
// 依赖清单只写在这里：plugin.json 的 dependencies 与 README 引用同一份。
import QtQuick
import qs.Common

QtObject {
    readonly property var requiredCommands: ["ydotool", "fcitx5"]
    // inline-keyboard-status addon 装在用户级目录（无需 root）。它负责把 fcitx5 的
    // 候选/预编辑写成 JSON，缺了候选栏就永远空着。
    // 相对 $HOME 的路径，由 shell 侧展开（QtObject 里拿不到 Quickshell.env）
    readonly property var requiredRelPaths: [
        ".local/lib/fcitx5/inline-keyboard-status.so",
        ".local/share/fcitx5/addon/inline-keyboard-status.conf"
    ]

    // 缺词条时回退英文原串。读一次 pluginTranslations 让绑定随异步注册的
    // 插件翻译表刷新（见 KeyboardCard 里的同款注释）
    function tr(term) {
        if (typeof I18n === "undefined" || !I18n || !I18n.trFor)
            return term
        const table = I18n.pluginTranslations
        return table ? I18n.trFor("inlineKeyboard", term) : term
    }

    // 一次 sh -c 把所有缺失项打出来（只输出缺的）
    function probeCommand() {
        const commands = requiredCommands.join(" ")
        let cmd = "for c in " + commands + "; do command -v \"$c\" >/dev/null 2>&1"
                + " || printf '%s ' \"$c\"; done"
        for (let i = 0; i < requiredRelPaths.length; i++)
            cmd += "; test -f \"$HOME/" + requiredRelPaths[i]
                 + "\" || printf 'inline-keyboard-status '"
        return cmd
    }

    function check(done) {
        Proc.runCommand("inlineKeyboard.depCheck", ["sh", "-c", probeCommand()],
            (stdout, exitCode) => {
                const missing = String(stdout || "").trim()
                if (missing === "") {
                    done(null)
                    return
                }
                done(tr("Inline Keyboard requires: %1").arg(missing))
            })
    }
}
