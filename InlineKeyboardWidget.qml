import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins
import qs.Services
import qs.Widgets

// Optional DankBar pill. Toggles the same global var the daemon owns, so the
// pill and `dms ipc call inlineKeyboard toggle` never disagree.
PluginComponent {
    id: root

    // 宿主按 "popoutService" in item 判断是否注入，不声明就永远拿不到
    property var popoutService: null

    property bool keyboardOpen: PluginService.getGlobalVar(root.pluginId, "open", false)

    pillClickAction: () => {
        PluginService.setGlobalVar(root.pluginId, "open", !root.keyboardOpen);
    }
    verticalBarPill: horizontalBarPill

    Connections {
        function onGlobalVarChanged(pluginId, varName) {
            if (pluginId === root.pluginId && varName === "open")
                root.keyboardOpen = PluginService.getGlobalVar(root.pluginId, "open", false);

        }

        target: PluginService
    }

    horizontalBarPill: Component {
        DIcon {
            name: "keyboard"
            size: root.iconSize
            // pill 没有底色，激活色要用 primary（在浅底和深底上都有对比），onPrimary 是白的会看不见
            color: root.keyboardOpen ? Theme.primary : Theme.surfaceText
        }

    }

}
