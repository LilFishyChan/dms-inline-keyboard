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
            // pill 激活态底色是 primary，图标必须用 onPrimary 才看得清
            color: root.keyboardOpen ? Theme.onPrimary : Theme.surfaceText
        }

    }

}
