// 插件启用前的依赖检查。
//
// 只检查**必需**依赖：ydotool。没有它键盘一个字符都打不出来。
// fcitx5 和 inline-keyboard-status addon 是**可选**的——缺了只是没有候选和输入法切换，
// 键盘本体（键位、快捷栏、设置）仍然可用，不该因此禁用整个插件。
import QtQuick
import qs.Common

QtObject {
    // 必需：缺了插件完全没法用
    readonly property var requiredCommands: ["ydotool"]

    // 缺词条时回退英文原串。读一次 pluginTranslations 让绑定随异步注册的
    // 插件翻译表刷新（见 KeyboardCard 里的同款注释）
    function tr(term) {
        if (typeof I18n === "undefined" || !I18n || !I18n.trFor)
            return term
        const table = I18n.pluginTranslations
        return table ? I18n.trFor("inlineKeyboard", term) : term
    }

    // 一次 sh -c 把缺失的必需项打出来（只输出缺的）
    function probeCommand() {
        const commands = requiredCommands.join(" ")
        let cmd = "for c in " + commands + "; do command -v \"$c\" >/dev/null 2>&1"
                + " || printf '%s ' \"$c\"; done"
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
