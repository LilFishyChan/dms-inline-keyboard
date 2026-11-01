// 插件启用前的依赖检查。
// 只检查**必需**依赖：ydotool。没有它键盘一个字符都打不出来。
import QtQuick
import qs.Common

QtObject {
    // 必需：缺了插件完全没法用
    readonly property var requiredCommands: ["ydotool"]

    // 一次 sh -c 把缺失的必需项打出来（只输出缺的）
    function probeCommand() {
        const commands = requiredCommands.join(" ");
        let cmd = "for c in " + commands + "; do command -v \"$c\" >/dev/null 2>&1" + " || printf '%s ' \"$c\"; done";
        return cmd;
    }

    function check(done) {
        Proc.runCommand("inlineKeyboard.depCheck", ["sh", "-c", probeCommand()], (stdout, exitCode) => {
            const missing = String(stdout || "").trim();
            if (missing === "") {
                done(null);
                return ;
            }
            done(tr("Inline Keyboard requires: %1").arg(missing));
        });
    }

}
